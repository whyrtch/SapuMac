import Foundation

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String
    public let size: Int64
}

/// Daftar aplikasi terpasang dan file sisanya di ~/Library.
public struct AppScanner: Sendable {
    public let locations: Locations

    public init(locations: Locations = Locations()) {
        self.locations = locations
    }

    public func installedApps() -> [InstalledApp] {
        var bundles: [URL] = []
        let fm = FileManager.default
        for folder in locations.applicationFolders {
            let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles])) ?? []
            for entry in entries {
                if entry.pathExtension == "app" {
                    bundles.append(entry)
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // Satu level subfolder, mis. /Applications/Adobe Photoshop/…app
                    let inner = (try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])) ?? []
                    bundles += inner.filter { $0.pathExtension == "app" }
                }
            }
        }

        return bundles.compactMap { url -> InstalledApp? in
            if Task.isCancelled { return nil }
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !id.hasPrefix("com.apple."), id != "com.personal.sapumac" else { return nil }
            let info = bundle.infoDictionary ?? [:]
            let name = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let version = (info["CFBundleShortVersionString"] as? String) ?? ""
            return InstalledApp(url: url, name: name, bundleID: id, version: version,
                                size: SizeCalculator.size(of: url))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// File sisa milik aplikasi di folder ~/Library yang diketahui.
    public func leftovers(for app: InstalledApp) -> [ScanItem] {
        let appName = app.url.deletingPathExtension().lastPathComponent
        var items: [ScanItem] = []
        for folder in locations.leftoverFolders {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [])) ?? []
            for entry in entries where Self.isLeftover(entry.lastPathComponent, bundleID: app.bundleID, appName: appName) {
                let size = SizeCalculator.size(of: entry)
                items.append(ScanItem(url: entry, size: size))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Nama cocok persis dengan bundle ID (atau turunannya), bukan sekadar awalan yang mirip.
    /// `com.foo.app` cocok dengan `com.foo.app.plist`, tetapi TIDAK dengan `com.foo.application`.
    public static func isLeftover(_ name: String, bundleID: String, appName: String) -> Bool {
        let n = name.lowercased()
        let b = bundleID.lowercased()
        if n == b || n.hasPrefix(b + ".") || n.hasSuffix("." + b) || n == "group." + b { return true }
        let a = appName.lowercased()
        return a.count >= 3 && n == a
    }
}
