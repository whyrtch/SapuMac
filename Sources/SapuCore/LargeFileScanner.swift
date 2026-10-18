import Foundation

/// Mencari file besar di home, melewati ~/Library, file tersembunyi, dan isi package (.app, .photoslibrary).
public struct LargeFileScanner: Sendable {
    public let locations: Locations

    public init(locations: Locations = Locations()) {
        self.locations = locations
    }

    public func scan(minSize: Int64, progress: (@Sendable (Int) -> Void)? = nil) -> [ScanItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey,
                                      .fileAllocatedSizeKey, .contentAccessDateKey]
        let skipped = [locations.library, locations.trash].map { PathUtil.resolved($0) }

        guard let e = FileManager.default.enumerator(
            at: locations.home, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [ScanItem] = []
        var visited = 0
        for case let url as URL in e {
            if Task.isCancelled { break }
            visited += 1
            if visited % 2000 == 0 { progress?(visited) }

            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isDirectory == true {
                if skipped.contains(PathUtil.resolved(url)) { e.skipDescendants() }
                continue
            }
            guard v.isRegularFile == true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            if size >= minSize {
                found.append(ScanItem(url: url, size: size, lastAccess: v.contentAccessDate))
            }
        }
        progress?(visited)
        return found.sorted { $0.size > $1.size }
    }

    public enum FileKind: String, CaseIterable, Sendable {
        case all = "Semua", video = "Video", archive = "Arsip", diskImage = "Disk image",
             audio = "Audio", image = "Gambar", document = "Dokumen", other = "Lainnya"

        static let extensions: [FileKind: Set<String>] = [
            .video: ["mp4", "mov", "m4v", "mkv", "avi", "webm", "braw", "mxf"],
            .archive: ["zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2"],
            .diskImage: ["dmg", "iso", "img", "pkg", "vmdk", "qcow2", "sparseimage"],
            .audio: ["mp3", "wav", "aiff", "flac", "m4a", "aac"],
            .image: ["jpg", "jpeg", "png", "heic", "tiff", "psd", "raw", "cr2", "nef", "arw"],
            .document: ["pdf", "doc", "docx", "ppt", "pptx", "key", "xls", "xlsx", "numbers", "pages"],
        ]

        public static func of(_ url: URL) -> FileKind {
            let ext = url.pathExtension.lowercased()
            return extensions.first { $0.value.contains(ext) }?.key ?? .other
        }
    }
}
