import Darwin
import Foundation

/// CPU, memory and disk usage, sampled every few seconds.
final class SystemStats: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var memory: Double = 0
    @Published private(set) var memoryUsedGB: Double = 0
    @Published private(set) var disk: Double = 0
    @Published private(set) var diskFreeGB: Double = 0

    private var previousTicks: (busy: UInt64, total: UInt64)?
    private var timer: Timer?

    init(live: Bool = true) {
        guard live else { return }
        sample()
        // CPU usage is a difference between two samples, so take the second one quickly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.sample() }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.sample() }
    }

    func showPreview(cpu: Double, memory: Double, memoryUsedGB: Double, disk: Double, diskFreeGB: Double) {
        self.cpu = cpu
        self.memory = memory
        self.memoryUsedGB = memoryUsedGB
        self.disk = disk
        self.diskFreeGB = diskFreeGB
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleDisk()
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
        disk = 1 - Double(free) / Double(total)
        diskFreeGB = Double(free) / 1_000_000_000
    }
}
