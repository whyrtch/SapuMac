import Foundation

/// Cara sebuah item boleh dihapus. SafetyGuard memeriksa path berdasarkan kebijakan ini.
public enum CleanPolicy: String, Sendable, Codable {
    /// File sampah otomatis (cache, log, temp). Hanya di dalam allowlist.
    case junk
    /// File yang dipilih sendiri oleh pengguna (Large & Old Files), di dalam home.
    case userFile
    /// Aplikasi beserta file sisanya.
    case uninstall
    /// Isi Trash. Satu-satunya kebijakan yang menghapus permanen.
    case trashBin
}

public struct ScanItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    public let lastAccess: Date?

    public init(url: URL, size: Int64, lastAccess: Date? = nil) {
        self.url = url
        self.size = size
        self.lastAccess = lastAccess
    }

    public var name: String { url.lastPathComponent }
    /// Untuk pengurutan tabel (Optional tidak Comparable).
    public var lastAccessSort: Date { lastAccess ?? .distantPast }
}

public struct ScanCategory: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let policy: CleanPolicy
    public let selectedByDefault: Bool
    public var items: [ScanItem]

    public init(id: String, title: String, detail: String, symbol: String,
                policy: CleanPolicy, selectedByDefault: Bool, items: [ScanItem]) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.policy = policy
        self.selectedByDefault = selectedByDefault
        self.items = items
    }

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

public extension Int64 {
    var formattedBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
