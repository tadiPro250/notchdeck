import SwiftUI

struct ExpandedView: View {
    @ObservedObject var model: NotchModel
    let player: NowPlaying
    let tray: FileTray
    let volume: VolumeControl
    let brightness: BrightnessControl
    let system: SystemStatus
    let actions: QuickActions

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: model.geometry.notchSize.height)
            Group {
                switch model.tab {
                case .home:
                    HomeView(model: model, player: player, system: system, tray: tray)
                case .tray:
                    TrayView(model: model, tray: tray)
                case .controls:
                    ControlsView(model: model, volume: volume, brightness: brightness, actions: actions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .frame(width: NotchModel.expandedContentSize.width,
               height: NotchModel.expandedContentSize.height, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(NotchTab.allCases) { tab in
                    TabButton(tab: tab, selected: model.tab == tab) { model.tab = tab }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: model.geometry.hasNotch ? model.geometry.notchSize.width : 16)
            StatusCluster(system: system)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 22)
    }
}

private struct TabButton: View {
    let tab: NotchTab
    let selected: Bool
    let action: () -> Void
    @StateObject private var hovering = ViewState<Bool>(false)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .semibold))
                if selected {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : (hovering.value ? 0.07 : 0))))
            .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering.value = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
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
                        .foregroundStyle(level <= 20 && !system.onPower ? .red : .white)
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
