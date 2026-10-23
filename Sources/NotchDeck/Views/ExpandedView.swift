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
                case .tray:
                    TrayView(model: model, tray: services.tray)
                case .calendar:
                    CalendarTabView(calendar: services.calendar)
                case .clipboard:
                    ClipboardView(history: services.clipboard, settings: settings)
                case .mirror:
                    MirrorView(camera: services.camera)
                case .controls:
                    ControlsView(model: model, services: services)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .id(model.tab)
            .transition(.opacity)
        }
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.18), value: model.tab)
        .frame(width: NotchModel.expandedContentSize.width,
               height: NotchModel.expandedContentSize.height, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(settings.visibleTabs) { tab in
                    TabButton(tab: tab, selected: model.tab == tab) { model.tab = tab }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: model.geometry.hasNotch ? model.geometry.notchSize.width : 16)
            HStack(spacing: 10) {
                StatusCluster(system: services.system)
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
    let action: () -> Void
    @StateObject private var hovering = ViewState<Bool>(false)
    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 32, height: 24)
                .background(Capsule().fill(selected ? look.accent.opacity(0.22)
                                                    : Color.white.opacity(hovering.value ? 0.08 : 0)))
                .foregroundStyle(selected ? look.accent : .white.opacity(0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .onHover { hovering.value = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
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

    var body: some View {
        HStack(spacing: 10) {
            if let level = system.batteryLevel {
                HStack(spacing: 4) {
                    Text("\(level)%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                    Image(systemName: batterySymbol(level))
                        .font(.system(size: 13))
                        .foregroundStyle(level <= 20 && !system.onPower ? .red : (system.isCharging ? .green : .white))
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
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
