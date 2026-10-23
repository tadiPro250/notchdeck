import SwiftUI

/// CPU/GPU/RAM/disk, network speed, battery health and accessory batteries.
struct SystemView: View {
    let services: NotchServices

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            GaugesColumn(stats: services.stats)
                .frame(width: 236)
            NetworkAndBattery(stats: services.stats, system: services.system)
                .frame(width: 190)
            DevicesColumn(accessories: services.accessories)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GaugesColumn: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Usage")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                StatGauge(label: "CPU", value: stats.cpu, detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores")
                StatGauge(label: "GPU", value: stats.gpu, detail: stats.gpuCores.map { "\($0) cores" } ?? "GPU")
                StatGauge(label: "RAM", value: stats.memory, detail: String(format: "%.1f GB", stats.memoryUsedGB))
                StatGauge(label: "Disk", value: stats.disk, detail: String(format: "%.0f GB free", stats.diskFreeGB))
            }
        }
    }
}

private struct NetworkAndBattery: View {
    @ObservedObject var stats: SystemStats
    @ObservedObject var system: SystemStatus
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Network")
            HStack(spacing: 10) {
                rate(symbol: "arrow.down", value: stats.downloadRate, color: .green)
                rate(symbol: "arrow.up", value: stats.uploadRate, color: .orange)
            }
            SectionTitle(text: "Battery").padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                row("Health", stats.batteryHealth.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                    tint: (stats.batteryHealth ?? 1) < 0.8 ? .orange : look.accent)
                row("Cycles", stats.batteryCycles.map(String.init) ?? "—")
                if let temperature = stats.batteryTemperature {
                    row("Temperature", String(format: "%.1f °C", temperature))
                }
                if let maximum = stats.batteryMaxMAh, let design = stats.batteryDesignMAh {
                    row("Capacity", "\(maximum) / \(design) mAh")
                }
                row("Charge", system.batteryLevel.map { "\($0)%" + (system.isCharging ? " ⚡︎" : "") } ?? "—")
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look.theme.surface))
        }
    }

    private func rate(symbol: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Text(SystemStats.rateText(value))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(look.theme.surface))
    }

    private func row(_ label: String, _ value: String, tint: Color = .white) -> some View {
        HStack {
            Text(label).foregroundStyle(look.theme.secondaryText)
            Spacer()
            Text(value).foregroundStyle(tint).monospacedDigit()
        }
        .font(.system(size: 10.5, weight: .medium))
    }
}

private struct DevicesColumn: View {
    @ObservedObject var accessories: AccessoryBatteries
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(text: "Devices")
                IconButton(symbol: "arrow.clockwise", help: "Refresh") { accessories.refresh() }
            }
            if accessories.accessories.isEmpty {
                Text("Connected AirPods, mice, keyboards and trackpads show their battery here.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(look.theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(accessories.accessories) { accessory in
                            HStack(spacing: 8) {
                                Image(systemName: accessory.symbol)
                                    .font(.system(size: 13))
                                    .frame(width: 20)
                                    .foregroundStyle(look.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(accessory.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                    Text(accessory.summary)
                                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                        .foregroundStyle((accessory.lowest ?? 100) <= 20 ? .red : look.theme.secondaryText)
                                }
                                Spacer(minLength: 0)
                                if let lowest = accessory.lowest {
                                    LevelBar(level: Double(lowest) / 100, color: lowest <= 20 ? .red : .green)
                                        .frame(width: 34, height: 5)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(look.theme.surface))
                        }
                    }
                }
            }
        }
        .onAppear { accessories.refresh() }
    }
}
