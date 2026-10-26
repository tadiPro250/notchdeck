import Darwin
import Foundation
import IOKit

/// CPU, GPU, memory and disk usage, sampled every few seconds.
final class SystemStats: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var gpu: Double = 0
    @Published private(set) var gpuMemoryGB: Double = 0
    @Published private(set) var gpuCores: Int?
    @Published private(set) var memory: Double = 0
    @Published private(set) var memoryUsedGB: Double = 0
    @Published private(set) var disk: Double = 0
    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0
    @Published private(set) var batteryHealth: Double?
    @Published private(set) var batteryCycles: Int?
    @Published private(set) var batteryTemperature: Double?
    @Published private(set) var batteryDesignMAh: Int?
    @Published private(set) var batteryMaxMAh: Int?
    @Published private(set) var diskFreeGB: Double = 0

    private var previousTicks: (busy: UInt64, total: UInt64)?
    private var previousNetwork: (received: UInt64, sent: UInt64, at: Date)?
    private var timer: Timer?
    private var diskSampledAt = Date.distantPast

    init(live: Bool = true) {
        guard live else { return }
        sample()
        // CPU usage is a difference between two samples, so take the second one quickly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sample() }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.sample() }
    }

    func showPreview(network: (down: Double, up: Double), battery: (health: Double, cycles: Int, temperature: Double)) {
        downloadRate = network.down
        uploadRate = network.up
        batteryHealth = battery.health
        batteryCycles = battery.cycles
        batteryTemperature = battery.temperature
    }

    func showPreview(cpu: Double, gpu: Double, gpuCores: Int, memory: Double, memoryUsedGB: Double, disk: Double, diskFreeGB: Double) {
        self.cpu = cpu
        self.gpu = gpu
        self.gpuCores = gpuCores
        self.memory = memory
        self.memoryUsedGB = memoryUsedGB
        self.disk = disk
        self.diskFreeGB = diskFreeGB
    }

    private func sample() {
        sampleCPU()
        sampleGPU()
        sampleMemory()
        // Free space barely moves, and asking for it is slow (macOS works out what's purgeable),
        // so once a minute, off the main thread.
        if Date().timeIntervalSince(diskSampledAt) > 60 {
            diskSampledAt = Date()
            DispatchQueue.global(qos: .utility).async { [weak self] in self?.sampleDisk() }
        }
        sampleNetwork()
        sampleBattery()
    }

    /// Bytes per second across all non-loopback interfaces.
    private func sampleNetwork() {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return }
        defer { freeifaddrs(pointer) }
        var received: UInt64 = 0, sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  (Int32(entry.pointee.ifa_flags) & IFF_LOOPBACK) == 0,
                  let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        let now = Date()
        if let previous = previousNetwork {
            let seconds = max(now.timeIntervalSince(previous.at), 0.5)
            // The 32-bit counters wrap; ignore that sample rather than show nonsense.
            if received >= previous.received, sent >= previous.sent {
                downloadRate = Double(received - previous.received) / seconds
                uploadRate = Double(sent - previous.sent) / seconds
            }
        }
        previousNetwork = (received, sent, now)
    }

    /// Health, cycle count and temperature from the battery controller.
    private func sampleBattery() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        // Newer Macs keep the raw figures inside a nested BatteryData dictionary.
        let nested = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        func value(_ key: String) -> Int? {
            (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int)
                ?? (nested?[key] as? Int)
        }
        let design = value("DesignCapacity")
        let maximum = value("AppleRawMaxCapacity") ?? value("NominalChargeCapacity")
        batteryDesignMAh = design
        batteryMaxMAh = maximum
        if let design, let maximum, design > 0 { batteryHealth = min(Double(maximum) / Double(design), 1) }
        batteryCycles = value("CycleCount")
        if let temperature = value("Temperature") { batteryTemperature = Double(temperature) / 100 }
    }

    static func rateText(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        if let previous = previousTicks, total > previous.total {
            cpu = Double(busy - previous.busy) / Double(total - previous.total)
        }
        previousTicks = (busy, total)
    }

    /// Apple silicon's GPU driver publishes live utilisation on its IOAccelerator service;
    /// reading it needs no special privileges.
    private func sampleGPU() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
                == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                              kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                  let utilization = stats["Device Utilization %"] as? Int else { continue }
            gpu = Double(utilization) / 100
            gpuMemoryGB = Double(stats["In use system memory"] as? Int ?? 0) / 1_073_741_824
            if gpuCores == nil {
                gpuCores = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString,
                                                           kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
            }
            return
        }
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count))
            * UInt64(pageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        memory = total > 0 ? Double(used) / Double(total) : 0
        memoryUsedGB = Double(used) / 1_073_741_824
    }

    private func sampleDisk() {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity, total > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.disk = 1 - Double(free) / Double(total)
            self?.diskFreeGB = Double(free) / 1_000_000_000
        }
    }
}
