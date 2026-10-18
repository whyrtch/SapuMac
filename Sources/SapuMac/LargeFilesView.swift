import SwiftUI
import SapuCore

@MainActor @Observable
final class LargeFilesModel {
    enum Age: Int, CaseIterable, Identifiable {
        case any = 0, month3 = 90, month6 = 180, year1 = 365
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .any: "Kapan saja"
            case .month3: "> 3 bulan"
            case .month6: "> 6 bulan"
            case .year1: "> 1 tahun"
            }
        }
    }

    static let sizeOptions: [Int] = [50, 100, 250, 500, 1000]
    static let scanFloorMB = 50

    let services: Services
    var items: [ScanItem] = []
    var scanning = false
    var scanned = false
    var visited = 0
    var minSizeMB = UserDefaults.standard.integer(forKey: "largeMinMB").nonZero ?? 100
    var age: Age = .any
    var kind: LargeFileScanner.FileKind = .all
    var selection: Set<URL> = []
    var sortOrder = [KeyPathComparator(\ScanItem.size, order: .reverse)]
    var failureBox: ReportBox?
    private var task: Task<Void, Never>?

    init(services: Services) { self.services = services }

    var filtered: [ScanItem] {
        let minBytes = Int64(minSizeMB) * 1_000_000
        let cutoff = Date().addingTimeInterval(-Double(age.rawValue) * 86400)
        return items.filter { item in
            item.size >= minBytes
                && (age == .any || item.lastAccessSort < cutoff)
                && (kind == .all || LargeFileScanner.FileKind.of(item.url) == kind)
        }
        .sorted(using: sortOrder)
    }

    var selectedItems: [ScanItem] { items.filter { selection.contains($0.url) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() {
        task?.cancel()
        scanning = true
        visited = 0
        selection = []
        let scanner = LargeFileScanner(locations: services.locations)
        let floor = Int64(Self.scanFloorMB) * 1_000_000
        task = Task {
            let found = await Task.detached(priority: .userInitiated) {
                scanner.scan(minSize: floor) { n in
                    Task { @MainActor in self.visited = n }
                }
            }.value
            if Task.isCancelled { return }
            items = found
            scanning = false
            scanned = true
        }
    }

    func cancel() { task?.cancel(); scanning = false }

    func trashSelected() {
        let chosen = selectedItems
        let cleaner = services.cleaner
        Task {
            let report = await Task.detached { cleaner.clean(chosen, policy: .userFile) }.value
            items.removeAll { report.removedURLs.contains($0.url) }
            selection.subtract(report.removedURLs)
            if !report.failures.isEmpty { failureBox = ReportBox(report: report) }
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

struct LargeFilesView: View {
    @Bindable var model: LargeFilesModel
    @State private var confirm = false
    private let module = Module.largeFiles

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeader(module: module)
            if model.scanning {
                ScanningView(module: module, progress: 0.5, text: "Memeriksa \(model.visited) file…") { model.cancel() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.scanned {
                VStack(spacing: 20) {
                    Spacer()
                    BigCircleButton(title: "Scan", module: module) { model.scan() }
                    Text("Memindai folder home Anda (kecuali ~/Library). Tidak ada yang dihapus otomatis.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                filters
                table
                footer
            }
        }
        .confirmationDialog("Pindahkan \(model.selection.count) file (\(model.selectedSize.formattedBytes)) ke Trash?",
                            isPresented: $confirm) {
            Button("Pindahkan ke Trash", role: .destructive) { model.trashSelected() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("File masih bisa dikembalikan dari Trash.")
        }
        .sheet(item: $model.failureBox) { box in
            FailureList(failures: box.report.failures) { model.failureBox = nil }
        }
    }

    private var filters: some View {
        HStack(spacing: 16) {
            Picker("Ukuran", selection: $model.minSizeMB) {
                ForEach(LargeFilesModel.sizeOptions, id: \.self) { mb in
                    Text(mb >= 1000 ? "≥ \(mb / 1000) GB" : "≥ \(mb) MB").tag(mb)
                }
            }
            .frame(width: 170)
            Picker("Dibuka", selection: $model.age) {
                ForEach(LargeFilesModel.Age.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 190)
            Picker("Jenis", selection: $model.kind) {
                ForEach(LargeFileScanner.FileKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 180)
            Spacer()
            Button("Scan ulang") { model.scan() }
        }
    }

    private var table: some View {
        Table(model.filtered, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Nama", value: \.name) { item in
                HStack(spacing: 8) {
                    FileIcon(url: item.url, size: 18)
                    Text(item.name).lineLimit(1)
                }
            }
            .width(min: 180, ideal: 260)
            TableColumn("Ukuran", value: \.size) { item in
                Text(item.size.formattedBytes).monospacedDigit()
            }
            .width(90)
            TableColumn("Terakhir dibuka", value: \.lastAccessSort) { item in
                Text(item.lastAccess.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
            }
            .width(120)
            TableColumn("Lokasi") { item in
                Text(item.url.deletingLastPathComponent().tildePath)
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            if let url = urls.first { Button("Tampilkan di Finder") { url.revealInFinder() } }
        }
        .scrollContentBackground(.hidden)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack {
            Text("\(model.filtered.count) file · total \(model.filtered.reduce(Int64(0)) { $0 + $1.size }.formattedBytes)")
                .foregroundStyle(.secondary)
            Spacer()
            PrimaryActionButton(title: model.selection.isEmpty ? "Pilih file untuk dihapus"
                                    : "Pindahkan ke Trash (\(model.selectedSize.formattedBytes))",
                                module: module, disabled: model.selection.isEmpty) { confirm = true }
        }
    }
}

struct ReportBox: Identifiable {
    let id = UUID()
    let report: CleanReport
}
