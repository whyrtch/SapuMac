import SwiftUI
import AppKit
import SapuCore

/// Model untuk Smart Scan, Sampah Sistem, dan Trash: Scan → Tinjau → Bersihkan → Ringkasan.
@MainActor @Observable
final class CleanupModel {
    enum Kind { case smart, junk, trash }
    enum Phase { case idle, scanning, results, cleaning, done(CleanReport) }

    let kind: Kind
    let services: Services
    var phase: Phase = .idle
    var categories: [ScanCategory] = []
    var selected: Set<URL> = []
    var progress: Double = 0
    var progressText = ""
    var activeLoginAgents = 0
    private var task: Task<Void, Never>?

    init(kind: Kind, services: Services) {
        self.kind = kind
        self.services = services
    }

    var totalSize: Int64 { categories.reduce(0) { $0 + $1.totalSize } }
    var selectedSize: Int64 {
        categories.flatMap(\.items).filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }
    var selectionIncludesPermanent: Bool {
        categories.contains { $0.policy == .trashBin && $0.items.contains { selected.contains($0.url) } }
    }

    func scan() {
        task?.cancel()
        phase = .scanning
        categories = []
        selected = []
        progress = 0

        let loc = services.locations
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let scanner = JunkScanner(locations: loc, runningBundleIDs: running)
        let steps: [(String, @Sendable () -> [ScanCategory])]
        switch kind {
        case .smart:
            steps = [("Memindai file sampah sistem…", { scanner.scanSystemJunk() }),
                     ("Memindai sampah developer…", { scanner.scanDeveloperJunk() }),
                     ("Memeriksa Trash…", { [scanner.scanTrash()] })]
        case .junk:
            steps = [("Memindai file sampah sistem…", { scanner.scanSystemJunk() }),
                     ("Memindai sampah developer…", { scanner.scanDeveloperJunk() })]
        case .trash:
            steps = [("Memeriksa Trash…", { [scanner.scanTrash()] })]
        }
        let kind = self.kind

        task = Task {
            var result: [ScanCategory] = []
            for (i, step) in steps.enumerated() {
                progressText = step.0
                let found = await Task.detached(priority: .userInitiated) { step.1() }.value
                if Task.isCancelled { return }
                result += found.filter { !$0.items.isEmpty }
                progress = Double(i + 1) / Double(steps.count)
            }
            if kind == .smart {
                activeLoginAgents = await Task.detached {
                    LaunchAgentManager(locations: loc).list().filter(\.enabled).count
                }.value
            }
            if Task.isCancelled { return }
            categories = result
            // Trash selalu dipilih di modul Trash; di Smart Scan tidak (hapus permanen).
            selected = Set(result.filter { $0.selectedByDefault || kind == .trash }.flatMap { $0.items.map(\.url) })
            phase = .results
        }
    }

    func cancel() {
        task?.cancel()
        phase = .idle
    }

    func reset() { phase = .idle; categories = []; selected = [] }

    func clean() {
        phase = .cleaning
        let work = categories.map { cat in (cat.policy, cat.items.filter { selected.contains($0.url) }) }
        let cleaner = services.cleaner
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                var total = CleanReport()
                for (policy, items) in work where !items.isEmpty {
                    total.merge(cleaner.clean(items, policy: policy))
                }
                return total
            }.value
            phase = .done(report)
        }
    }

    // MARK: Pilihan

    func state(of cat: ScanCategory) -> TriCheckbox.State {
        let n = cat.items.filter { selected.contains($0.url) }.count
        return n == 0 ? .none : n == cat.items.count ? .all : .some
    }

    func toggle(_ cat: ScanCategory) {
        let urls = cat.items.map(\.url)
        if state(of: cat) == .all { selected.subtract(urls) } else { selected.formUnion(urls) }
    }

    func toggle(_ item: ScanItem) {
        if selected.contains(item.url) { selected.remove(item.url) } else { selected.insert(item.url) }
    }
}

struct CleanupModuleView: View {
    let module: Module
    @Bindable var model: CleanupModel
    var openLoginItems: (() -> Void)? = nil
    @State private var confirmPermanent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ModuleHeader(module: module)
            switch model.phase {
            case .idle:
                idle
            case .scanning:
                center { ScanningView(module: module, progress: model.progress, text: model.progressText) { model.cancel() } }
            case .results:
                results
            case .cleaning:
                center { ProgressView("Membersihkan…").controlSize(.large) }
            case .done(let report):
                center { DoneView(module: module, report: report) { model.reset() } }
            }
        }
        .confirmationDialog("Hapus isi Trash secara permanen?", isPresented: $confirmPermanent) {
            Button("Hapus permanen & bersihkan", role: .destructive) { model.clean() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Item Trash yang dipilih tidak bisa dikembalikan. Item lain dipindah ke Trash seperti biasa.")
        }
    }

    private var idle: some View {
        VStack(spacing: 24) {
            if module == .smartScan || module == .trash { FullDiskAccessBanner() }
            Spacer()
            BigCircleButton(title: "Scan", module: module) { model.scan() }
                .frame(maxWidth: .infinity)
            Text(idleHint).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private var idleHint: String {
        switch module {
        case .trash: "Lihat berapa besar isi Trash Anda."
        case .smartScan: "Memindai sampah sistem, sampah developer, Trash, dan item login."
        default: "Hanya membaca dulu — tidak ada yang dihapus sebelum Anda menekan Bersihkan."
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.categories.isEmpty {
                center {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(module.accent)
                        Text("Bersih! Tidak ada yang perlu dibersihkan.").font(.title3)
                        Button("Scan lagi") { model.scan() }
                    }
                }
            } else {
                summaryCards
                categoryList
                HStack {
                    Button("Scan ulang") { model.scan() }.buttonStyle(.bordered)
                    Spacer()
                    PrimaryActionButton(title: "Bersihkan \(model.selectedSize.formattedBytes)", module: module,
                                        disabled: model.selected.isEmpty) {
                        if model.selectionIncludesPermanent { confirmPermanent = true } else { model.clean() }
                    }
                }
            }
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Pembersihan", systemImage: "externaldrive.badge.xmark").foregroundStyle(Module.systemJunk.accent)
                Text(model.totalSize.formattedBytes).font(.system(size: 30, weight: .bold, design: .rounded))
                Text("ditemukan · \(model.selectedSize.formattedBytes) dipilih").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            if module == .smartScan {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Kecepatan", systemImage: "power").foregroundStyle(Module.loginItems.accent)
                    Text("\(model.activeLoginAgents)").font(.system(size: 30, weight: .bold, design: .rounded))
                    HStack {
                        Text("launch agent aktif").foregroundStyle(.secondary)
                        if let openLoginItems { Button("Tinjau") { openLoginItems() }.buttonStyle(.link) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }

    private var categoryList: some View {
        List {
            ForEach(model.categories) { cat in
                DisclosureGroup {
                    ForEach(cat.items) { item in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { model.selected.contains(item.url) },
                                                     set: { _ in model.toggle(item) }))
                                .toggleStyle(.checkbox).labelsHidden()
                            FileIcon(url: item.url, size: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).lineLimit(1)
                                Text(item.url.tildePath).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(item.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .contextMenu { Button("Tampilkan di Finder") { item.url.revealInFinder() } }
                    }
                } label: {
                    HStack(spacing: 10) {
                        TriCheckbox(state: model.state(of: cat)) { model.toggle(cat) }
                        Image(systemName: cat.symbol).frame(width: 20).foregroundStyle(module.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cat.title).font(.headline)
                            Text(cat.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(cat.totalSize.formattedBytes).font(.headline).monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    private func center<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        v().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
