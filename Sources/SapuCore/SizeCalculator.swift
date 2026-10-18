import Foundation

public enum SizeCalculator {
    static let keys: [URLResourceKey] = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey,
    ]

    /// Ukuran yang benar-benar terpakai di disk. Symlink dihitung 0 dan tidak diikuti.
    public static func size(of url: URL) -> Int64 {
        guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if v.isSymbolicLink == true { return 0 }
        if v.isDirectory != true { return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0) }

        var total: Int64 = 0
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        for case let file as URL in e {
            if Task.isCancelled { break }
            guard let rv = try? file.resourceValues(forKeys: Set(keys)),
                  rv.isDirectory != true, rv.isSymbolicLink != true else { continue }
            total += Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
        }
        return total
    }
}
