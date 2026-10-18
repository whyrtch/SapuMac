import Foundation

public struct CleanReport: Sendable {
    public struct Failure: Sendable, Identifiable {
        public let id = UUID()
        public let url: URL
        public let reason: String
    }

    public var bytes: Int64 = 0
    public var count = 0
    public var permanentlyDeleted = false
    public var failures: [Failure] = []
    public var removedURLs: Set<URL> = []

    public init() {}

    public mutating func merge(_ other: CleanReport) {
        bytes += other.bytes
        count += other.count
        permanentlyDeleted = permanentlyDeleted || other.permanentlyDeleted
        failures += other.failures
        removedURLs.formUnion(other.removedURLs)
    }
}

/// Catatan lokal setiap pembersihan: waktu, aksi, ukuran, path.
public struct CleanupLog: Sendable {
    public let file: URL

    public init(locations: Locations = Locations()) {
        file = locations.sapuLogDir.appendingPathComponent("cleanup.log")
    }

    public func record(_ action: String, url: URL, size: Int64) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(action)\t\(size)\t\(url.path)\n"
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}

/// Satu-satunya jalur hapus di app. Setiap item lewat SafetyGuard dulu.
public struct Cleaner: Sendable {
    public let safety: SafetyGuard
    public let log: CleanupLog

    public init(safety: SafetyGuard, log: CleanupLog) {
        self.safety = safety
        self.log = log
    }

    public func clean(_ items: [ScanItem], policy: CleanPolicy) -> CleanReport {
        var report = CleanReport()
        let fm = FileManager.default
        for item in items {
            do {
                try safety.check(item.url, policy: policy)
                if policy == .trashBin {
                    try fm.removeItem(at: item.url)
                    log.record("DELETE", url: item.url, size: item.size)
                    report.permanentlyDeleted = true
                } else {
                    try fm.trashItem(at: item.url, resultingItemURL: nil)
                    log.record("TRASH", url: item.url, size: item.size)
                }
                report.bytes += item.size
                report.count += 1
                report.removedURLs.insert(item.url)
            } catch {
                report.failures.append(.init(url: item.url, reason: error.localizedDescription))
                log.record("SKIP", url: item.url, size: item.size)
            }
        }
        return report
    }
}
