import Foundation

/// Memindai file sampah sistem, sampah developer, dan Trash. Hanya membaca, tidak menghapus.
public struct JunkScanner: Sendable {
    public let locations: Locations
    /// Bundle ID aplikasi yang sedang berjalan; cache-nya dilewati.
    public let runningBundleIDs: Set<String>

    /// Cache package manager di ~/Library/Caches, masuk kategori developer.
    static let packageCacheNames: Set<String> = ["Yarn", "pip", "Homebrew", "node-gyp", "pnpm"]
    static let ownNames: Set<String> = ["SapuMac", "com.personal.sapumac"]

    public init(locations: Locations = Locations(), runningBundleIDs: Set<String> = []) {
        self.locations = locations
        self.runningBundleIDs = runningBundleIDs
    }

    // MARK: - Kategori

    public func scanSystemJunk() -> [ScanCategory] {
        let l = locations
        let caches = children(l.caches).filter { url in
            let n = url.lastPathComponent
            return !n.hasPrefix("com.apple.")
                && !Self.packageCacheNames.contains(n)
                && !Self.ownNames.contains(n)
                && !runningBundleIDs.contains(n)
        }
        let logs = children(l.logs).filter {
            let n = $0.lastPathComponent
            return n != "DiagnosticReports" && !Self.ownNames.contains(n) && !n.hasPrefix("com.apple.")
        }
        let dayAgo = Date().addingTimeInterval(-24 * 3600)
        let temp = children(l.temp).filter { url in
            guard !url.lastPathComponent.hasPrefix("com.apple.") else { return false }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (modified ?? .distantFuture) < dayAgo
        }

        return [
            ScanCategory(id: "user-cache", title: "Cache aplikasi",
                         detail: "File sementara yang dibuat ulang otomatis oleh aplikasi",
                         symbol: "shippingbox", policy: .junk, selectedByDefault: true,
                         items: makeItems(caches)),
            ScanCategory(id: "user-logs", title: "Log pengguna",
                         detail: "Catatan aktivitas aplikasi yang sudah tidak diperlukan",
                         symbol: "doc.text", policy: .junk, selectedByDefault: true,
                         items: makeItems(logs)),
            ScanCategory(id: "crash-reports", title: "Laporan crash",
                         detail: "Laporan diagnostik lama dari aplikasi yang pernah crash",
                         symbol: "exclamationmark.triangle", policy: .junk, selectedByDefault: true,
                         items: makeItems(children(l.crashReports))),
            ScanCategory(id: "temp", title: "File sementara",
                         detail: "File temporer yang berumur lebih dari 24 jam",
                         symbol: "clock.arrow.circlepath", policy: .junk, selectedByDefault: true,
                         items: makeItems(temp)),
        ]
    }

    public func scanDeveloperJunk() -> [ScanCategory] {
        let l = locations
        let packages = Self.packageCacheNames.sorted().map { l.caches.appendingPathComponent($0) }
            + [l.npmDir.appendingPathComponent("_cacache")]
        let existingPackages = packages.filter { FileManager.default.fileExists(atPath: $0.path) }

        return [
            ScanCategory(id: "derived-data", title: "Xcode DerivedData",
                         detail: "Hasil build Xcode; dibuat ulang saat build berikutnya",
                         symbol: "hammer", policy: .junk, selectedByDefault: true,
                         items: makeItems(children(l.derivedData))),
            ScanCategory(id: "simulator-caches", title: "Cache Simulator",
                         detail: "Cache iOS Simulator",
                         symbol: "iphone", policy: .junk, selectedByDefault: true,
                         items: makeItems(children(l.simulatorCaches))),
            ScanCategory(id: "package-caches", title: "Cache package manager",
                         detail: "npm, Yarn, pnpm, pip, Homebrew",
                         symbol: "cube.box", policy: .junk, selectedByDefault: true,
                         items: makeItems(existingPackages)),
            ScanCategory(id: "xcode-archives", title: "Xcode Archives",
                         detail: "Arsip build lama; hapus hanya jika tidak perlu simbol debug",
                         symbol: "archivebox", policy: .junk, selectedByDefault: false,
                         items: makeItems(children(l.xcodeArchives))),
            ScanCategory(id: "device-support", title: "iOS DeviceSupport",
                         detail: "Simbol untuk perangkat iOS lama",
                         symbol: "cable.connector", policy: .junk, selectedByDefault: false,
                         items: makeItems(children(l.deviceSupport))),
        ]
    }

    public func scanTrash() -> ScanCategory {
        ScanCategory(id: "trash", title: "Trash",
                     detail: "Dihapus permanen; tidak bisa dikembalikan",
                     symbol: "trash", policy: .trashBin, selectedByDefault: false,
                     items: makeItems(children(locations.trash)))
    }

    // MARK: - Helper

    func children(_ dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
    }

    func makeItems(_ urls: [URL]) -> [ScanItem] {
        urls.compactMap { url -> ScanItem? in
            if Task.isCancelled { return nil }
            let size = SizeCalculator.size(of: url)
            return size > 0 ? ScanItem(url: url, size: size) : nil
        }
        .sorted { $0.size > $1.size }
    }
}
