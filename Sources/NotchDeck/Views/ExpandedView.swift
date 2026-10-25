import SwiftUI

struct ExpandedView: View {
    @ObservedObject var model: NotchModel
    let services: NotchServices
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: model.geometry.notchSize.height)
            Group {
                switch model.tab {
                case .home:
                    HomeView(model: model, services: services, settings: settings)
                case .widgets:
                    WidgetsView(model: model, services: services, settings: settings)
                case .tray:
                    TrayView(model: model, tray: services.tray)
                case .calendar:
                    CalendarTabView(calendar: services.calendar)
                case .clock:
                    ClockView(model: model, clock: services.clock, timer: services.timer, pomodoro: services.pomodoro,
                              settings: settings)
                case .tasks:
                    TasksView(model: model, tasks: services.tasks, pomodoro: services.pomodoro)
                case .desk:
                    DeskView(model: model, services: services, settings: settings)
                case .clipboard:
                    ClipboardView(history: services.clipboard, settings: settings)
                case .mirror:
                    MirrorView(camera: services.camera)
                case .controls:
                    ControlsView(model: model, services: services)
                case .system:
                    SystemView(services: services)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, settings.showQuickLaunch ? 6 : 20)
            .id(model.tab)
            .transition(.asymmetric(insertion: .popIn(scale: 0.97), removal: .opacity.animation(.easeIn(duration: 0.1))))
            if settings.showQuickLaunch {
                QuickLaunchRow(model: model, settings: settings)
                    .frame(height: NotchModel.dockHeight, alignment: .top)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(photoShadow ? 0.55 : 0), radius: 2, y: 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.tab)
        .frame(width: model.expandedSize.width, height: model.expandedSize.height, alignment: .top)
    }

    private var photoShadow: Bool {
        settings.photoReadability && settings.backgroundMode != .theme && !settings.backgroundPhotos.isEmpty
    }

    private var header: some View {
        HStack(spacing: 0) {
            // Narrower buttons when many tabs share the space left of the notch.
            let tabs = settings.visibleTabs
            let room = (model.expandedSize.width - 40 - (model.geometry.hasNotch ? model.geometry.notchSize.width : 16)) / 2
            let width = min(27, max(19, room / CGFloat(max(tabs.count, 1))))
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    TabButton(tab: tab, selected: model.tab == tab, width: width) { model.tab = tab }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: model.geometry.hasNotch ? model.geometry.notchSize.width : 16)
            HStack(spacing: 10) {
                StatusCluster(system: services.system, battery: settings.headerBattery, clock: settings.headerClock)
                IconButton(symbol: "gearshape.fill", help: "Settings") { model.openSettings() }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
    }
}

private struct TabButton: View {
    let tab: NotchTab
    let selected: Bool
    var width: CGFloat = 27
    let action: () -> Void
    @StateObject private var hovering = ViewState<Bool>(false)
    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: width, height: 24)
                .background(Capsule().fill(selected ? look.accent.opacity(0.22)
                                                    : Color.white.opacity(hovering.value ? 0.08 : 0)))
                .scaleEffect(hovering.value && !selected ? 1.08 : 1)
                .foregroundStyle(selected ? look.accent : .white.opacity(0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .onHover { hovering.value = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selected)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering.value)
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    let action: () -> Void
    @StateObject private var hovering = ViewState<Bool>(false)

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(hovering.value ? 0.12 : 0)))
                .foregroundStyle(.white.opacity(hovering.value ? 0.95 : 0.55))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering.value = $0 }
    }
}

private struct StatusCluster: View {
    @ObservedObject var system: SystemStatus
    var battery = true
    var clock = true

    var body: some View {
        HStack(spacing: 10) {
            if battery, let level = system.batteryLevel {
                HStack(spacing: 4) {
                    Text("\(level)%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                    Image(systemName: batterySymbol(level))
                        .font(.system(size: 13))
                        .foregroundStyle(level <= 20 && !system.onPower ? .red : (system.isCharging ? .green : .white))
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            if clock {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }
        }
    }

    private func batterySymbol(_ level: Int) -> String {
        if system.isCharging { return "battery.100.bolt" }
        switch level {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        case 13...: return "battery.25"
        default: return "battery.0"
        }
    }
}
