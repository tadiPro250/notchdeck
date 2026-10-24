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
                .frame(width: 250)
            divider
            TimerColumn(timer: timer)
                .frame(width: 180)
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
    @StateObject private var seconds = ViewState<Int>(0)
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 7) {
            ColumnHeader(title: "Timer", symbol: "timer") {
                if !timer.isActive {
                    Text("⌥ scroll = sec").foregroundStyle(.white.opacity(0.35)).font(.system(size: 9, weight: .medium))
                }
            }
            if timer.isActive {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    ZStack {
                        Circle().stroke(look.theme.surface, lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: 1 - timer.progress(at: context.date))
                            .stroke(look.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: look.accent.opacity(0.5), radius: 6)
                        Text(FocusTimer.clock(timer.remaining(at: context.date)))
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .frame(width: 104, height: 104)
                    .animation(.easeInOut(duration: 0.4), value: timer.remaining(at: context.date))
                }
                HStack(spacing: 6) {
                    Button(timer.isPaused ? "Resume" : "Pause") { timer.togglePause() }.buttonStyle(PillButtonStyle())
                    Button("Stop") { timer.cancel() }.buttonStyle(PillButtonStyle())
                }
            } else {
                HStack(spacing: 2) {
                    DrumWheel(value: $minutes.value, range: 0...180, unit: "min", seconds: false) { delta, alternate in
                        if alternate { step(seconds: delta) } else { step(minutes: delta) }
                    }
                    Text(":")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .offset(y: -6)
                    DrumWheel(value: $seconds.value, range: 0...59, unit: "sec", seconds: true) { delta, _ in
                        step(seconds: delta)
                    }
                }
                .frame(height: 104)
                HStack(spacing: 4) {
                    ForEach([1, 5, 10, 25], id: \.self) { preset in
                        Button("\(preset)m") {
                            minutes.value = preset
                            seconds.value = 0
                        }
                        .buttonStyle(ChipStyle(selected: minutes.value == preset && seconds.value == 0))
                    }
                }
                Button {
                    timer.start(minutes: Double(minutes.value) + Double(seconds.value) / 60)
                } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentPillStyle())
                .disabled(minutes.value == 0 && seconds.value == 0)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: timer.isActive)
    }

    private func step(minutes delta: Int) {
        minutes.value = min(max(minutes.value + delta, 0), 180)
    }

    /// Seconds wrap into minutes, so scrolling past 59 carries over.
    private func step(seconds delta: Int) {
        let total = min(max(minutes.value * 60 + seconds.value + delta, 0), 180 * 60)
        minutes.value = total / 60
        seconds.value = total % 60
    }
}

/// A picker drum: the value large in the middle, its neighbours fading above and below. Scroll
/// it with the trackpad or a mouse wheel; the closure says whether ⌥ or ⌃ was held.
private struct DrumWheel: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    let seconds: Bool
    let onStep: (Int, Bool) -> Void
    @StateObject private var hovering = ViewState<Bool>(false)
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 0) {
            neighbour(value - 2, opacity: 0.12)
            neighbour(value - 1, opacity: 0.32)
            Text(format(value))
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(value)))
                .frame(height: 36)
            neighbour(value + 1, opacity: 0.32)
            neighbour(value + 2, opacity: 0.12)
            Text(unit.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(hovering.value ? look.accent : .white.opacity(0.35))
                .padding(.top, 1)
        }
        .frame(width: 62)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(hovering.value ? 0.1 : 0.05))
            .frame(height: 38)
            .offset(y: -6))
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25),
                                     .init(color: .black, location: 0.75), .init(color: .black.opacity(0.9), location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .overlay(ScrollCatcher { delta, alternate in onStep(delta, alternate) })
        .onHover { hovering.value = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: value)
        .help(seconds ? "Scroll to set seconds" : "Scroll to set minutes; hold ⌥ or ⌃ for seconds")
    }

    private func neighbour(_ n: Int, opacity: Double) -> some View {
        Text(range.contains(n) ? format(n) : " ")
            .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(opacity))
            .frame(height: 14)
    }

    private func format(_ n: Int) -> String { String(format: "%02d", n) }
}

/// Turns scroll-wheel and trackpad scrolling into whole steps.
struct ScrollCatcher: NSViewRepresentable {
    let onStep: (Int, Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.onStep = onStep }

    final class CatcherView: NSView {
        var onStep: ((Int, Bool) -> Void)?
        private var accumulated: CGFloat = 0

        override func scrollWheel(with event: NSEvent) {
            guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else {
                super.scrollWheel(with: event)
                return
            }
            let alternate = !event.modifierFlags.intersection([.option, .control]).isEmpty
            var steps = 0
            if event.hasPreciseScrollingDeltas {
                if event.phase == .began { accumulated = 0 }
                accumulated += event.scrollingDeltaY
                let threshold: CGFloat = 12
                while abs(accumulated) >= threshold {
                    steps += accumulated > 0 ? -1 : 1
                    accumulated -= accumulated > 0 ? threshold : -threshold
                }
            } else if event.scrollingDeltaY != 0 {
                steps = event.scrollingDeltaY > 0 ? -1 : 1
            }
            guard steps != 0 else { return }
            onStep?(steps, alternate)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}

struct ChipStyle: ButtonStyle {
    var selected = false
    @Environment(\.look) private var look

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(selected ? .black : .white.opacity(0.8))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(selected ? look.accent : Color.white.opacity(configuration.isPressed ? 0.2 : 0.09)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct AccentPillStyle: ButtonStyle {
    @Environment(\.look) private var look
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(look.accent.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.3)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
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
