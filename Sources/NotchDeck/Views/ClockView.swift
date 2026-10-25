import SwiftUI

/// Alarms, timer and stopwatch side by side.
struct ClockView: View {
    let model: NotchModel
    @ObservedObject var clock: ClockCenter
    @ObservedObject var timer: FocusTimer
    let pomodoro: PomodoroTimer
    @ObservedObject var settings: AppSettings
    @StateObject private var focusMode: ViewState<Bool>
    @Environment(\.look) private var look

    init(model: NotchModel, clock: ClockCenter, timer: FocusTimer, pomodoro: PomodoroTimer, settings: AppSettings) {
        self.model = model
        self.clock = clock
        self.timer = timer
        self.pomodoro = pomodoro
        self.settings = settings
        // Opens on Focus while a Pomodoro is under way.
        _focusMode = StateObject(wrappedValue: ViewState(pomodoro.isActive))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AlarmsColumn(model: model, clock: clock)
                .frame(width: 250)
            divider
            VStack(spacing: 6) {
                ModeSwitch(focus: $focusMode.value)
                if focusMode.value {
                    PomodoroColumn(pomodoro: pomodoro, settings: settings)
                } else {
                    TimerColumn(timer: timer)
                }
            }
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
    @StateObject private var hours = ViewState<Int>(0)
    @StateObject private var minutes = ViewState<Int>(10)
    @StateObject private var seconds = ViewState<Int>(0)
    @Environment(\.look) private var look

    private static let limit = 23 * 3600 + 59 * 60 + 59
    private var total: Int { hours.value * 3600 + minutes.value * 60 + seconds.value }

    var body: some View {
        VStack(spacing: 7) {
            if !timer.isActive {
                Text("Scroll each drum · ⌥ scroll = seconds")
                    .foregroundStyle(.white.opacity(0.35)).font(.system(size: 9, weight: .medium))
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
                            .font(.system(size: timer.remaining(at: context.date) >= 3600 ? 17 : 20,
                                          weight: .semibold, design: .rounded).monospacedDigit())
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
                HStack(spacing: 1) {
                    DrumWheel(value: $hours.value, range: 0...23, unit: "hr", help: "Scroll to set hours",
                              width: 50, size: 25) { delta, alternate in
                        step(by: alternate ? delta : delta * 3600)
                    }
                    colon
                    DrumWheel(value: $minutes.value, range: 0...59, unit: "min", width: 50, size: 25) { delta, alternate in
                        step(by: alternate ? delta : delta * 60)
                    }
                    colon
                    DrumWheel(value: $seconds.value, range: 0...59, unit: "sec", seconds: true, width: 50, size: 25) { delta, _ in
                        step(by: delta)
                    }
                }
                .frame(height: 104)
                HStack(spacing: 4) {
                    ForEach([(60, "1m"), (300, "5m"), (1500, "25m"), (3600, "1h")], id: \.1) { preset in
                        Button(preset.1) { set(preset.0) }
                            .buttonStyle(ChipStyle(selected: total == preset.0))
                    }
                }
                Button {
                    timer.start(minutes: Double(total) / 60)
                } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentPillStyle())
                .disabled(total == 0)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: timer.isActive)
    }

    private var colon: some View {
        Text(":")
            .font(.system(size: 21, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .offset(y: -6)
    }

    /// Every drum moves the same total, so 59 s + 1 rolls into the next minute and so on.
    private func step(by delta: Int) {
        set(total + delta)
    }

    private func set(_ seconds: Int) {
        let clamped = min(max(seconds, 0), Self.limit)
        hours.value = clamped / 3600
        minutes.value = clamped / 60 % 60
        self.seconds.value = clamped % 60
    }
}

/// A picker drum: the value large in the middle, its neighbours fading above and below. Scroll
/// it with the trackpad or a mouse wheel; the closure says whether ⌥ or ⌃ was held.
struct DrumWheel: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    var seconds = false
    /// Tooltip; the timer's own wording when nil.
    var help: String?
    var width: CGFloat = 62
    /// Point size of the middle number.
    var size: CGFloat = 30
    /// Values shown above and below: 2, or 1 where height is tight.
    var neighbours = 2
    let onStep: (Int, Bool) -> Void
    @StateObject private var hovering = ViewState<Bool>(false)
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 0) {
            if neighbours > 1 { neighbour(value - 2, opacity: 0.12) }
            neighbour(value - 1, opacity: 0.32)
            Text(format(value))
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(value)))
                .frame(height: 36)
            neighbour(value + 1, opacity: 0.32)
            if neighbours > 1 { neighbour(value + 2, opacity: 0.12) }
            Text(unit.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(hovering.value ? look.accent : .white.opacity(0.35))
                .padding(.top, 1)
        }
        .frame(width: width)
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
        .help(help ?? (seconds ? "Scroll to set seconds" : "Scroll to set minutes; hold ⌥ or ⌃ for seconds"))
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
            .background(Capsule().fill(selected ? look.accent : Color.black.opacity(0.3))
                .overlay(Capsule().fill(selected ? .clear : Color.white.opacity(configuration.isPressed ? 0.2 : 0.1))))
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

/// Timer or Focus (Pomodoro), at the top of the middle column.
private struct ModeSwitch: View {
    @Binding var focus: Bool
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 2) {
            segment("Timer", "timer", selected: !focus) { focus = false }
            segment("Focus", "brain.head.profile", selected: focus) { focus = true }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focus)
    }

    private func segment(_ title: String, _ symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .foregroundStyle(selected ? look.accent : .white.opacity(0.55))
                .background(Capsule().fill(selected ? look.accent.opacity(0.2) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Pomodoro

private struct PomodoroColumn: View {
    @ObservedObject var pomodoro: PomodoroTimer
    @ObservedObject var settings: AppSettings

    var body: some View {
        let tint = pomodoro.phase.isBreak ? Color.green : Color(red: 1, green: 0.42, blue: 0.38)
        VStack(spacing: 7) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                ZStack {
                    Circle().stroke(tint.opacity(0.18), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: pomodoro.isActive ? 1 - pomodoro.progress(at: context.date) : 1)
                        .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: tint.opacity(0.5), radius: 6)
                    VStack(spacing: 0) {
                        Text(pomodoro.phase.title.uppercased())
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(tint)
                        Text(FocusTimer.clock(pomodoro.remaining(at: context.date)))
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
                .frame(width: 96, height: 96)
                .animation(.easeInOut(duration: 0.4), value: pomodoro.remaining(at: context.date))
            }
            // A dot per round: filled when done, ringed for the one under way.
            HStack(spacing: 5) {
                ForEach(1...pomodoro.rounds, id: \.self) { index in
                    Circle()
                        .fill(index < pomodoro.round || (index == pomodoro.round && pomodoro.phase.isBreak)
                              ? tint : Color.white.opacity(0.15))
                        .overlay(Circle().strokeBorder(index == pomodoro.round ? tint : .clear, lineWidth: 1.2))
                        .frame(width: 7, height: 7)
                }
                Text("\(pomodoro.completedToday) today")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 4)
            }
            HStack(spacing: 6) {
                Button {
                    pomodoro.togglePause()
                } label: {
                    Label(pomodoro.isRunning ? "Pause" : (pomodoro.isPaused ? "Resume" : "Start"),
                          systemImage: pomodoro.isRunning ? "pause.fill" : "play.fill")
                        .frame(width: 70)
                }
                .buttonStyle(AccentPillStyle())
                IconButton(symbol: "forward.end.fill", help: "Skip to the next phase") { pomodoro.skip() }
                IconButton(symbol: "arrow.counterclockwise", help: "Start over") { pomodoro.reset() }
            }
            Text("\(settings.pomodoroWork) · \(settings.pomodoroShortBreak) · \(settings.pomodoroLongBreak) min")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .help("Work · short break · long break; change them in Settings → Clock")
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
