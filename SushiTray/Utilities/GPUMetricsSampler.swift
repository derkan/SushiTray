import Foundation
import IOKit

enum GPUMetricsSampler {
    struct Snapshot {
        var utilization: Double
        var memoryUsedBytes: UInt64
        var memoryTotalBytes: UInt64
        var memoryFraction: Double
    }

    static func sample() -> Snapshot? {
        guard let stats = readPerformanceStatistics() else { return nil }

        let utilPercent = doubleValue(stats["Device Utilization %"])
            ?? doubleValue(stats["Renderer Utilization %"])
            ?? 0
        let alloc = uint64Value(stats["Alloc system memory"]) ?? 0
        let total = physicalMemoryBytes()
        guard total > 0 else { return nil }

        return Snapshot(
            utilization: min(max(utilPercent / 100.0, 0), 1),
            memoryUsedBytes: alloc,
            memoryTotalBytes: total,
            memoryFraction: min(max(Double(alloc) / Double(total), 0), 1)
        )
    }

    private static func readPerformanceStatistics() -> [String: Any]? {
        let matching = IOServiceMatching("AGXAccelerator")
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            if let stats = performanceStatistics(for: service) {
                return stats
            }
        }
        return nil
    }

    /// Only fetches `PerformanceStatistics` — not the entire IORegistry property bag.
    private static func performanceStatistics(for service: io_registry_entry_t) -> [String: Any]? {
        let key = "PerformanceStatistics" as CFString
        guard let cf = IORegistryEntryCreateCFProperty(
            service,
            key,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return cf.takeRetainedValue() as? [String: Any]
    }

    private static func physicalMemoryBytes() -> UInt64 {
        UInt64(ProcessInfo.processInfo.physicalMemory)
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let i as Int: return Double(i)
        case let d as Double: return d
        case let f as Float: return Double(f)
        default: return nil
        }
    }

    private static func uint64Value(_ any: Any?) -> UInt64? {
        switch any {
        case let n as NSNumber: return n.uint64Value
        case let i as Int: return UInt64(i)
        case let u as UInt64: return u
        case let i64 as Int64: return UInt64(max(0, i64))
        default: return nil
        }
    }
}
