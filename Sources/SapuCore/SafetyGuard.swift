import Foundation

public enum SafetyError: Error, LocalizedError, Equatable {
    case protectedPath(String)
    case outsideAllowed(String)
    case notRegularFile(String)

    public var errorDescription: String? {
        switch self {
        case .protectedPath(let p): "Lokasi dilindungi, tidak boleh dihapus: \(p)"
        case .outsideAllowed(let p): "Di luar lokasi yang diizinkan: \(p)"
        case .notRegularFile(let p): "Bukan file biasa: \(p)"
        }
    }
}

/// Satu-satunya pintu sebelum file dihapus. Lebih baik melewatkan file daripada menghapus yang salah.
public struct SafetyGuard: Sendable {
    public let locations: Locations

    public init(locations: Locations = Locations()) {
        self.locations = locations
    }

    /// Tidak pernah disentuh, apa pun kebijakannya.
    var alwaysProtected: [URL] {
        ["/System", "/usr", "/bin", "/sbin", "/private/etc", "/private/var/db", "/Library"]
            .map { URL(fileURLWithPath: $0) }
        + [
            locations.lib("Keychains"),
            locations.lib("Mobile Documents"),   // iCloud Drive
            locations.lib("Mail"),
            locations.lib("Messages"),
            locations.home("Pictures/Photos Library.photoslibrary"),
        ]
    }

    /// Tambahan untuk pembersihan otomatis: dokumen pribadi pengguna.
    var protectedForAutomatic: [URL] {
        [locations.home("Documents"), locations.home("Desktop")]
    }

    public func allowedRoots(for policy: CleanPolicy) -> [URL] {
        let l = locations
        switch policy {
        case .junk:
            return [l.caches, l.logs, l.derivedData, l.xcodeArchives, l.deviceSupport,
                    l.simulatorCaches, l.npmDir, l.temp]
        case .uninstall:
            return l.applicationFolders + l.leftoverFolders
        case .trashBin:
            return [l.trash]
        case .userFile:
            return [l.home]
        }
    }

    public func check(_ url: URL, policy: CleanPolicy) throws {
        let path = PathUtil.resolved(url)

        var protected = alwaysProtected
        if policy != .userFile { protected += protectedForAutomatic }
        for root in protected where PathUtil.isInside(path, PathUtil.resolved(root), strict: false) {
            throw SafetyError.protectedPath(path)
        }

        let inAllowed = allowedRoots(for: policy).contains {
            PathUtil.isInside(path, PathUtil.resolved($0), strict: true)
        }
        guard inAllowed else { throw SafetyError.outsideAllowed(path) }

        if policy == .userFile {
            // File pilihan pengguna: tidak boleh di ~/Library dan harus file biasa (bukan folder).
            if PathUtil.isInside(path, PathUtil.resolved(locations.library), strict: false) {
                throw SafetyError.protectedPath(path)
            }
            let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { throw SafetyError.notRegularFile(path) }
        }
    }

    public func isAllowed(_ url: URL, policy: CleanPolicy) -> Bool {
        (try? check(url, policy: policy)) != nil
    }
}
