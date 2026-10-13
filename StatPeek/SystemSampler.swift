import Darwin
import Foundation
import IOKit

final class SystemSampler {
    private var previousCPU: CPUTicks?

    func resetCPU() { previousCPU = nil }

    func sample(_ metrics: Set<Metric>) -> MetricSnapshot {
        var snapshot = MetricSnapshot()
        for metric in Metric.allCases where metrics.contains(metric) {
            if metric == .disk {
                snapshot.disk = DiskSpaceReader.snapshot()?.capacity
                snapshot.readings[metric] = snapshot.disk.map { DiskFormatter.format(bytes: $0.availableBytes) } ?? "不可用"
                snapshot.percentages[metric] = snapshot.disk?.usedPercentage
                continue
            }
            let value: Double?
            switch metric {
            case .cpu: value = cpuUsage()
            case .memory: value = memoryUsage()
            case .gpu: value = gpuUsage()
            case .disk: value = nil
            }
            snapshot.readings[metric] = metric == .cpu && previousCPU != nil && cpuIsWarming
                ? "采样中…" : MetricMath.percentage(value)
            if let value, value.isFinite, (0...100).contains(value) { snapshot.percentages[metric] = value }
        }
        return snapshot
    }

    private var cpuIsWarming = false

    private func cpuUsage() -> Double? {
        cpuIsWarming = false
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var stats = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size
                                          / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { previousCPU = nil; return nil }
        let current = CPUTicks(user: stats.cpu_ticks.0, system: stats.cpu_ticks.1,
                               idle: stats.cpu_ticks.2, nice: stats.cpu_ticks.3)
        let previous = previousCPU
        previousCPU = current
        guard let previous else { cpuIsWarming = true; return nil }
        return current.utilization(since: previous)
    }

    private func memoryUsage() -> Double? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
                                          / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS else {
            return nil
        }
        return MetricMath.memoryUsage(active: UInt64(stats.active_count),
                                      wired: UInt64(stats.wire_count),
                                      compressed: UInt64(stats.compressor_page_count),
                                      purgeable: UInt64(stats.purgeable_count),
                                      pageSize: UInt64(pageSize),
                                      physical: ProcessInfo.processInfo.physicalMemory)
    }

    private func gpuUsage() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var readings: [Double] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                              kCFAllocatorDefault, 0)?.takeRetainedValue(),
               let statistics = property as? [String: Any],
               let usage = statistics["Device Utilization %"] as? NSNumber {
                readings.append(usage.doubleValue)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return MetricMath.gpuUsage(from: readings)
    }
}
