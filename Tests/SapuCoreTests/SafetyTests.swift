import Testing
import Foundation
@testable import SapuCore

/// Home palsu di folder sementara: semua uji hapus berjalan di sini, tidak pernah di home asli.
final class Fixture {
    let root: URL
    let loc: Locations

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapumac-tests-\(UUID().uuidString)")
        loc = Locations(home: root.appendingPathComponent("home"), temp: root.appendingPathComponent("tmp"))
        for dir in ["home/Library/Caches", "home/Library/Logs", "home/Library/Keychains", "home/Documents",
                    "home/Desktop", "home/Movies", "home/.Trash", "tmp"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func file(_ rel: String, bytes: Int = 4096) throws -> URL {
        let url = loc.home(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    var safety: SafetyGuard { SafetyGuard(locations: loc) }
}

@Suite("SafetyGuard")
struct SafetyGuardTests {
    @Test("S-01: dokumen ditolak untuk pembersihan otomatis")
    func rejectsDocuments() throws {
        let f = try Fixture()
        let doc = try f.file("Documents/x.pdf")
        #expect(throws: SafetyError.self) { try f.safety.check(doc, policy: .junk) }
        #expect(throws: SafetyError.self) { try f.safety.check(doc, policy: .uninstall) }
    }

    @Test("S-02: symlink di Caches yang menunjuk ke Documents ditolak")
    func rejectsSymlinkEscape() throws {
        let f = try Fixture()
        let target = try f.file("Documents/penting.txt")
        let link = f.loc.caches.appendingPathComponent("jebakan")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: SafetyError.self) { try f.safety.check(link, policy: .junk) }
    }

    @Test("S-03: path dengan .. dinormalisasi lalu ditolak")
    func rejectsDotDot() throws {
        let f = try Fixture()
        try f.file("Desktop/foto.jpg")
        let sneaky = URL(fileURLWithPath: f.loc.caches.path + "/../../Desktop/foto.jpg")
        #expect(throws: SafetyError.self) { try f.safety.check(sneaky, policy: .junk) }
    }

    @Test("Item cache biasa diizinkan, folder Caches itu sendiri tidak")
    func cacheItemAllowedRootNot() throws {
        let f = try Fixture()
        let item = try f.file("Library/Caches/com.example.app/data.bin")
        #expect(f.safety.isAllowed(item.deletingLastPathComponent(), policy: .junk))
        #expect(!f.safety.isAllowed(f.loc.caches, policy: .junk))
    }

    @Test("Keychains selalu dilindungi")
    func keychainsProtected() throws {
        let f = try Fixture()
        let kc = try f.file("Library/Keychains/login.keychain-db")
        for policy in [CleanPolicy.junk, .userFile, .uninstall, .trashBin] {
            #expect(!f.safety.isAllowed(kc, policy: policy))
        }
    }

    @Test("File pilihan pengguna: file di Documents boleh, folder & ~/Library tidak")
    func userFilePolicy() throws {
        let f = try Fixture()
        let video = try f.file("Documents/video.mov")
        #expect(f.safety.isAllowed(video, policy: .userFile))
        #expect(!f.safety.isAllowed(f.loc.home("Documents"), policy: .userFile))
        let libFile = try f.file("Library/Caches/a.bin")
        #expect(!f.safety.isAllowed(libFile, policy: .userFile))
    }

    @Test("Sistem tidak pernah boleh")
    func systemPaths() throws {
        let f = try Fixture()
        for p in ["/System/Library/CoreServices", "/usr/bin/true", "/Library/Preferences"] {
            #expect(!f.safety.isAllowed(URL(fileURLWithPath: p), policy: .uninstall))
        }
    }
}

@Suite("Uninstaller")
struct LeftoverTests {
    @Test("S-06: bundle ID mirip tidak ikut terhapus")
    func similarBundleIDs() {
        let id = "com.foo.app"
        #expect(AppScanner.isLeftover("com.foo.app", bundleID: id, appName: "Foo"))
        #expect(AppScanner.isLeftover("com.foo.app.plist", bundleID: id, appName: "Foo"))
        #expect(AppScanner.isLeftover("com.foo.app.savedState", bundleID: id, appName: "Foo"))
        #expect(AppScanner.isLeftover("ABCDE12345.com.foo.app", bundleID: id, appName: "Foo"))
        #expect(!AppScanner.isLeftover("com.foo.application", bundleID: id, appName: "Foo"))
        #expect(!AppScanner.isLeftover("com.foo.application.plist", bundleID: id, appName: "Foo"))
        #expect(!AppScanner.isLeftover("Foobar", bundleID: id, appName: "Foo"))
    }

    @Test("Nama aplikasi terlalu pendek tidak dicocokkan")
    func shortNames() {
        #expect(!AppScanner.isLeftover("Go", bundleID: "com.x.go", appName: "Go"))
    }
}

@Suite("Scanner & Cleaner")
struct ScannerTests {
    @Test("S-04: cache aplikasi yang sedang berjalan dan cache Apple dilewati")
    func junkScannerSkips() throws {
        let f = try Fixture()
        try f.file("Library/Caches/com.example.idle/a.bin")
        try f.file("Library/Caches/com.example.running/a.bin")
        try f.file("Library/Caches/com.apple.Safari/a.bin")
        try f.file("Library/Caches/Homebrew/a.bin")
        let cats = JunkScanner(locations: f.loc, runningBundleIDs: ["com.example.running"]).scanSystemJunk()
        let names = cats.first { $0.id == "user-cache" }!.items.map(\.name)
        #expect(names == ["com.example.idle"])
    }

    @Test("Homebrew masuk kategori developer")
    func packageCaches() throws {
        let f = try Fixture()
        try f.file("Library/Caches/Homebrew/a.bin")
        let cats = JunkScanner(locations: f.loc).scanDeveloperJunk()
        #expect(cats.first { $0.id == "package-caches" }!.items.map(\.name) == ["Homebrew"])
    }

    @Test("Large files menemukan file besar dan melewati ~/Library")
    func largeFiles() throws {
        let f = try Fixture()
        try f.file("Movies/besar.mov", bytes: 3_000_000)
        try f.file("Movies/kecil.mov", bytes: 10_000)
        try f.file("Library/Caches/besar-juga.bin", bytes: 3_000_000)
        let found = LargeFileScanner(locations: f.loc).scan(minSize: 1_000_000)
        #expect(found.map(\.name) == ["besar.mov"])
    }

    @Test("Mengosongkan Trash hanya menghapus isi ~/.Trash")
    func emptyTrash() throws {
        let f = try Fixture()
        let inTrash = try f.file(".Trash/lama.zip")
        let doc = try f.file("Documents/jangan.txt")
        let cleaner = Cleaner(safety: f.safety, log: CleanupLog(locations: f.loc))
        let report = cleaner.clean([ScanItem(url: inTrash, size: 1), ScanItem(url: doc, size: 1)], policy: .trashBin)
        #expect(report.count == 1)
        #expect(report.failures.count == 1)
        #expect(!FileManager.default.fileExists(atPath: inTrash.path))
        #expect(FileManager.default.fileExists(atPath: doc.path))
        let log = try String(contentsOf: CleanupLog(locations: f.loc).file, encoding: .utf8)
        #expect(log.contains("DELETE") && log.contains("SKIP"))
    }

    @Test("Ukuran folder dihitung dari isinya, symlink tidak diikuti")
    func sizes() throws {
        let f = try Fixture()
        let a = try f.file("Library/Caches/pkg/a.bin", bytes: 100_000)
        try FileManager.default.createSymbolicLink(at: f.loc.caches.appendingPathComponent("pkg/link"),
                                                   withDestinationURL: f.loc.home("Documents"))
        let size = SizeCalculator.size(of: a.deletingLastPathComponent())
        #expect(size >= 100_000 && size < 200_000)
    }
}
