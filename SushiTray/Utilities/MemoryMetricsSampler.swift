import Foundation
import Darwin

enum MemoryMetricsSampler {
    struct Snapshot {
        var usedBytes: UInt64
        var totalBytes: UInt64
        var freeBytes: UInt64
        /// 0...1
        var usedFraction: Double
    }

    static func sample() -> Snapshot {
        let total = UInt64(ProcessInfo.processInfo.physicalMemory)
        let (free, used) = memoryUsage(total: total)
        return Snapshot(
            usedBytes: used,
            totalBytes: total,
            freeBytes: free,
            usedFraction: total > 0 ? min(max(Double(used) / Double(total), 0), 1) : 0
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

}
