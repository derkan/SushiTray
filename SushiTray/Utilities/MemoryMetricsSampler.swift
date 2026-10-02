import Foundation
import Darwin

enum MemoryMetricsSampler {
    struct Snapshot {
        var usedBytes: UInt64
        var totalBytes: UInt64
        var freeBytes: UInt64
        /// 0...1
        var usedFraction: Double
        /// 0...1 overall CPU load since last sample (nil on first call).
        var cpuFraction: Double?
    }

    private static var previousCPU: (user: Double, system: Double, idle: Double, nice: Double)?

    static func sample() -> Snapshot {
        let total = UInt64(ProcessInfo.processInfo.physicalMemory)
        let (free, used) = memoryUsage(total: total)
        let cpu = cpuUsage()
        return Snapshot(
            usedBytes: used,
            totalBytes: total,
            freeBytes: free,
            usedFraction: total > 0 ? min(max(Double(used) / Double(total), 0), 1) : 0,
            cpuFraction: cpu
        )
    }

    private static func memoryUsage(total: UInt64) -> (free: UInt64, used: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return (0, total)
        }
        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let freeTotal = free + speculative
        let used = total > freeTotal ? total - freeTotal : 0
        return (freeTotal, used)
    }

    private static func cpuUsage() -> Double? {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )
        guard kr == KERN_SUCCESS, let info = cpuInfo else { return nil }
        defer {
            let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var user: Double = 0
        var system: Double = 0
        var idle: Double = 0
        var nice: Double = 0
        let loadInfo = UnsafePointer(info).withMemoryRebound(
            to: processor_cpu_load_info.self,
            capacity: Int(numCPUs)
        ) { $0 }

        for i in 0..<Int(numCPUs) {
            user += Double(loadInfo[i].cpu_ticks.0) // CPU_STATE_USER
            system += Double(loadInfo[i].cpu_ticks.1) // CPU_STATE_SYSTEM
            idle += Double(loadInfo[i].cpu_ticks.2) // CPU_STATE_IDLE
            nice += Double(loadInfo[i].cpu_ticks.3) // CPU_STATE_NICE
        }

        defer {
            previousCPU = (user, system, idle, nice)
        }

        guard let prev = previousCPU else { return nil }
        let dUser = user - prev.user
        let dSystem = system - prev.system
        let dIdle = idle - prev.idle
        let dNice = nice - prev.nice
        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return nil }
        return min(max((dUser + dSystem + dNice) / total, 0), 1)
    }
}
