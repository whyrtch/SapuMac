import Foundation
import Darwin
import IOKit.ps

public struct SystemSnapshot: Sendable {
    public var cpu: Double            // 0...1
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    public var diskFree: Int64
    public var diskTotal: Int64
    public var batteryPercent: Int?
    public var charging: Bool

    public var memoryFraction: Double { memoryTotal == 0 ? 0 : Double(memoryUsed) / Double(memoryTotal) }
    public var diskUsedFraction: Double { diskTotal == 0 ? 0 : 1 - Double(diskFree) / Double(diskTotal) }
}

/// Membaca CPU, memori, disk, dan baterai. CPU dihitung dari selisih dua sampel.
public final class SystemSampler: @unchecked Sendable {
    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    public init() {}

    public func sample() -> SystemSnapshot {
        let battery = Self.battery()
        let disk = Self.disk()
        return SystemSnapshot(cpu: cpuUsage(), memoryUsed: Self.memoryUsed(),
                              memoryTotal: ProcessInfo.processInfo.physicalMemory,
                              diskFree: disk.free, diskTotal: disk.total,
                              batteryPercent: battery.percent, charging: battery.charging)
    }

    func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let t = info.cpu_ticks
        let now = (user: t.0, system: t.1, idle: t.2, nice: t.3)
        defer { previousTicks = now }
        guard let prev = previousTicks else { return 0 }
        let user = Double(now.user &- prev.user)
        let system = Double(now.system &- prev.system)
        let idle = Double(now.idle &- prev.idle)
        let nice = Double(now.nice &- prev.nice)
        let total = user + system + idle + nice
        return total > 0 ? (user + system + nice) / total : 0
    }

    static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let page = UInt64(getpagesize())
        // Seperti "Memory Used" di Activity Monitor: app memory + wired + compressed.
        let internalPages = UInt64(stats.internal_page_count), purgeable = UInt64(stats.purgeable_count)
        let app = internalPages > purgeable ? internalPages - purgeable : 0
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    static func disk() -> (free: Int64, total: Int64) {
        let v = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (v?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v?.volumeTotalCapacity ?? 0))
    }

    static func battery() -> (percent: Int?, charging: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false)
        }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (current * 100 / max, d[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return (nil, false)
    }
}

public enum Permissions {
    /// Full Disk Access terdeteksi bila database TCC sistem bisa dibuka untuk dibaca.
    public static func hasFullDiskAccess() -> Bool {
        let tcc = "/Library/Application Support/com.apple.TCC/TCC.db"
        if let h = FileHandle(forReadingAtPath: tcc) {
            try? h.close()
            return true
        }
        return false
    }

    public static let fullDiskAccessSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
