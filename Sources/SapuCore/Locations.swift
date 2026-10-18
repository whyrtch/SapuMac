import Foundation

/// Semua lokasi yang dipakai app, diturunkan dari home & temp agar bisa diganti di test.
public struct Locations: Sendable {
    public let home: URL
    public let temp: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                temp: URL = URL(fileURLWithPath: NSTemporaryDirectory())) {
        self.home = home
        self.temp = temp
    }

    public func home(_ path: String) -> URL { home.appendingPathComponent(path) }
    public func lib(_ path: String) -> URL { home.appendingPathComponent("Library").appendingPathComponent(path) }

    public var library: URL { home("Library") }
    public var caches: URL { lib("Caches") }
    public var logs: URL { lib("Logs") }
    public var crashReports: URL { lib("Logs/DiagnosticReports") }
    public var trash: URL { home(".Trash") }

    public var derivedData: URL { lib("Developer/Xcode/DerivedData") }
    public var xcodeArchives: URL { lib("Developer/Xcode/Archives") }
    public var deviceSupport: URL { lib("Developer/Xcode/iOS DeviceSupport") }
    public var simulatorCaches: URL { lib("Developer/CoreSimulator/Caches") }
    public var npmDir: URL { home(".npm") }

    /// Folder di ~/Library yang boleh berisi file sisa aplikasi.
    public var leftoverFolders: [URL] {
        ["Application Support", "Preferences", "Caches", "Containers", "Group Containers",
         "LaunchAgents", "Saved Application State", "Logs", "HTTPStorages", "WebKit"].map(lib)
    }

    public var applicationFolders: [URL] {
        [URL(fileURLWithPath: "/Applications"), home("Applications")]
    }

    public var sapuLogDir: URL { lib("Logs/SapuMac") }
    public var sapuSupportDir: URL { lib("Application Support/SapuMac") }
}

enum PathUtil {
    /// Path absolut dengan `..` dinormalisasi dan semua symlink di-resolve.
    /// Untuk path yang belum ada, leluhur terdekat yang ada di-resolve.
    static func resolved(_ url: URL) -> String {
        resolved(path: url.standardizedFileURL.path)
    }

    static func resolved(path: String) -> String {
        if let r = realpath(path, nil) {
            defer { free(r) }
            return String(cString: r)
        }
        let ns = path as NSString
        let parent = ns.deletingLastPathComponent
        if parent == path || parent.isEmpty { return path }
        return (resolved(path: parent) as NSString).appendingPathComponent(ns.lastPathComponent)
    }

    /// `strict`: path harus berada DI DALAM root, bukan root itu sendiri.
    static func isInside(_ path: String, _ root: String, strict: Bool) -> Bool {
        if path == root { return !strict }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }
}
