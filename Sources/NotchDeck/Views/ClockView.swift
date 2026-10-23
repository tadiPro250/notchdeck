import SwiftUI

/// Alarms, timer and stopwatch side by side.
struct ClockView: View {
    let model: NotchModel
    @ObservedObject var clock: ClockCenter
    @ObservedObject var timer: FocusTimer
    @ObservedObject var settings: AppSettings
    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AlarmsColumn(model: model, clock: clock)
                .frame(width: 270)
            divider
            TimerColumn(timer: timer)
                .frame(width: 170)
            divider
            StopwatchColumn(clock: clock)
                .frame(maxWidth: .infinity)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1).padding(.vertical, 4)
    }
}

private struct ColumnHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let trailing: Trailing
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(look.accent)
            Text(title.uppercased()).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 0)
            trailing
        }
        .font(.system(size: 10, weight: .bold))
        .frame(height: 20)
    }
}

// MARK: Alarms

private struct AlarmsColumn: View {
    let model: NotchModel
    @ObservedObject var clock: ClockCenter
    @StateObject private var adding = ViewState<Bool>(false)
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ColumnHeader(title: "Alarms", symbol: "alarm.fill") {
                IconButton(symbol: adding.value ? "xmark" : "plus", help: adding.value ? "Cancel" : "New alarm") {
                    adding.value.toggle()
                    if adding.value { model.requestKeyboard() }
                }
            }
            if adding.value {
                NewAlarmForm(clock: clock) { adding.value = false }
            } else if clock.alarms.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No alarms").font(.system(size: 13, weight: .semibold))
                    Text("Press + to set one. It rings here in the notch, with Snooze and Stop.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(look.theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(clock.alarms) { alarm in AlarmRow(alarm: alarm, clock: clock) }
                    }
                }
            }
        }
    }
}

private struct AlarmRow: View {
    let alarm: Alarm
    @ObservedObject var clock: ClockCenter
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(alarm.timeText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(alarm.enabled ? .white : .white.opacity(0.35))
                Text([alarm.label.isEmpty ? nil : alarm.label, alarm.repeatText,
                      alarm.snoozedUntil.map { "snoozed to " + $0.formatted(date: .omitted, time: .shortened) }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(look.theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { alarm.enabled }, set: { _ in clock.toggle(alarm) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(look.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look.theme.surface))
        .contextMenu {
            Button("Delete Alarm", role: .destructive) { clock.delete(alarm) }
        }
    }
}

private struct NewAlarmForm: View {
    @ObservedObject var clock: ClockCenter
    let done: () -> Void
    @StateObject private var time = ViewState<Date>(Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date())
    @StateObject private var label = ViewState<String>("")
    @StateObject private var days = ViewState<Set<Int>>([])
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                DatePicker("", selection: $time.value, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                TextField("Label", text: $label.value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { day in
                    let on = days.value.contains(day)
                    Button(String(Calendar.current.veryShortWeekdaySymbols[day - 1])) {
                        if on { days.value.remove(day) } else { days.value.insert(day) }
                    }
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 26, height: 22)
                    .background(Circle().fill(on ? look.accent : Color.white.opacity(0.1)))
                    .foregroundStyle(on ? .black : .white)
                    .buttonStyle(.plain)
                }
            }
            Button {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: time.value)
                clock.addAlarm(hour: parts.hour ?? 7, minute: parts.minute ?? 0, label: label.value, repeatDays: days.value)
                done()
            } label: {
                Label("Set alarm", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())
        }
    }
}

// MARK: Timer

private struct TimerColumn: View {
    @ObservedObject var timer: FocusTimer
    @StateObject private var minutes = ViewState<Int>(10)
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 8) {
            ColumnHeader(title: "Timer", symbol: "timer") { EmptyView() }
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                ZStack {
                    Circle().stroke(look.theme.surface, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: timer.isActive ? 1 - timer.progress(at: context.date) : 0)
                        .stroke(look.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(timer.isActive ? FocusTimer.clock(timer.remaining(at: context.date)) : "\(minutes.value):00")
                        .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .frame(width: 84, height: 84)
            }
            if timer.isActive {
                HStack(spacing: 6) {
                    Button(timer.isPaused ? "Resume" : "Pause") { timer.togglePause() }.buttonStyle(PillButtonStyle())
                    Button("Stop") { timer.cancel() }.buttonStyle(PillButtonStyle())
                }
            } else {
                HStack(spacing: 4) {
                    IconButton(symbol: "minus") { minutes.value = max(1, minutes.value - (minutes.value > 10 ? 5 : 1)) }
                    Button("Start") { timer.start(minutes: Double(minutes.value)) }.buttonStyle(PillButtonStyle())
                    IconButton(symbol: "plus") { minutes.value = min(180, minutes.value + (minutes.value >= 10 ? 5 : 1)) }
                }
            }
        }
    }
}

// MARK: Stopwatch

private struct StopwatchColumn: View {
    @ObservedObject var clock: ClockCenter
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ColumnHeader(title: "Stopwatch", symbol: "stopwatch.fill") { EmptyView() }
            TimelineView(.periodic(from: .now, by: 0.05)) { context in
                Text(ClockCenter.stopwatchText(clock.stopwatchElapsed(at: context.date)))
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(clock.stopwatchRunning ? .white : .white.opacity(clock.stopwatchActive ? 0.7 : 0.4))
            }
            HStack(spacing: 6) {
                Button(clock.stopwatchRunning ? "Stop" : (clock.stopwatchActive ? "Resume" : "Start")) {
                    clock.toggleStopwatch()
                }
                .buttonStyle(PillButtonStyle())
                Button(clock.stopwatchRunning ? "Lap" : "Reset") {
                    clock.stopwatchRunning ? clock.lap() : clock.resetStopwatch()
                }
                .buttonStyle(PillButtonStyle())
                .disabled(!clock.stopwatchActive)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(clock.laps.enumerated()), id: \.offset) { index, lap in
                        HStack {
                            Text("Lap \(clock.laps.count - index)")
                            Spacer()
                            Text(ClockCenter.stopwatchText(lap))
                        }
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
    }
}
