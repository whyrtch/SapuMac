import SwiftUI
import AppKit
import SapuCore

@MainActor @Observable
final class UninstallerModel {
    let services: Services
    var apps: [InstalledApp] = []
    var loading = false
    var loaded = false
    var search = ""
    var selectedID: URL?
    var files: [ScanItem] = []          // app bundle + file sisa
    var selectedFiles: Set<URL> = []
    var loadingFiles = false
    var lastReport: CleanReport?
    var failureBox: ReportBox?

    init(services: Services) { self.services = services }

    var filteredApps: [InstalledApp] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    var selectedApp: InstalledApp? { apps.first { $0.id == selectedID } }
    var selectedSize: Int64 { files.filter { selectedFiles.contains($0.url) }.reduce(0) { $0 + $1.size } }

    func isRunning(_ app: InstalledApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    func load() {
        loading = true
        let scanner = AppScanner(locations: services.locations)
        Task {
            apps = await Task.detached(priority: .userInitiated) { scanner.installedApps() }.value
            loading = false
            loaded = true
        }
    }

    func select(_ id: URL?) {
        selectedID = id
        lastReport = nil
        files = []
        selectedFiles = []
        guard let app = selectedApp else { return }
        loadingFiles = true
        let scanner = AppScanner(locations: services.locations)
        Task {
            let leftovers = await Task.detached { scanner.leftovers(for: app) }.value
            guard selectedID == app.id else { return }
            files = [ScanItem(url: app.url, size: app.size)] + leftovers
            selectedFiles = Set(files.map(\.url))
            loadingFiles = false
        }
    }

    func uninstall() {
        guard let app = selectedApp else { return }
        let chosen = files.filter { selectedFiles.contains($0.url) }
        let cleaner = services.cleaner
        Task {
            let report = await Task.detached { cleaner.clean(chosen, policy: .uninstall) }.value
            lastReport = report
            if !report.failures.isEmpty { failureBox = ReportBox(report: report) }
            if report.removedURLs.contains(app.url) {
                apps.removeAll { $0.id == app.id }
                selectedID = nil
                files = []
            } else {
                files.removeAll { report.removedURLs.contains($0.url) }
            }
        }
    }
}

struct UninstallerView: View {
    @Bindable var model: UninstallerModel
    @State private var confirm = false
    private let module = Module.uninstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeader(module: module)
            if model.loading || !model.loaded {
                ProgressView("Mengumpulkan daftar aplikasi…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    appList.frame(width: 300)
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let r = model.lastReport, r.count > 0 {
                Text("\(r.count) item (\(r.bytes.formattedBytes)) dipindah ke Trash.")
                    .foregroundStyle(module.accent)
            }
        }
        .onAppear { if !model.loaded && !model.loading { model.load() } }
        .confirmationDialog("Hapus \(model.selectedApp?.name ?? "") dan \(model.selectedFiles.count) item terkait?",
                            isPresented: $confirm) {
            Button("Uninstall (\(model.selectedSize.formattedBytes))", role: .destructive) { model.uninstall() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Semua item dipindah ke Trash dan masih bisa dikembalikan.")
        }
        .sheet(item: $model.failureBox) { box in
            FailureList(failures: box.report.failures) { model.failureBox = nil }
        }
    }

    private var appList: some View {
        VStack(spacing: 8) {
            TextField("Cari aplikasi", text: $model.search)
                .textFieldStyle(.roundedBorder)
            List(model.filteredApps, selection: Binding(get: { model.selectedID }, set: { model.select($0) })) { app in
                HStack(spacing: 10) {
                    FileIcon(url: app.url, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).lineLimit(1)
                        Text(app.size.formattedBytes).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(app.id)
            }
            .scrollContentBackground(.hidden)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            Text("\(model.apps.count) aplikasi · aplikasi bawaan Apple disembunyikan")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    FileIcon(url: app.url, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.title2.bold())
                        Text("\(app.bundleID)\(app.version.isEmpty ? "" : " · versi \(app.version)")")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if model.loadingFiles {
                    ProgressView("Mencari file sisa…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(model.files) { item in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { model.selectedFiles.contains(item.url) },
                                set: { on in
                                    if on { model.selectedFiles.insert(item.url) } else { model.selectedFiles.remove(item.url) }
                                }))
                                .toggleStyle(.checkbox).labelsHidden()
                                .disabled(item.url == app.url) // bundle aplikasi wajib ikut
                            FileIcon(url: item.url, size: 18)
                            Text(item.url.tildePath).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(item.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .contextMenu { Button("Tampilkan di Finder") { item.url.revealInFinder() } }
                    }
                    .scrollContentBackground(.hidden)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    HStack {
                        if model.isRunning(app) {
                            Label("Tutup aplikasi ini dulu sebelum uninstall.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.yellow)
                        }
                        Spacer()
                        PrimaryActionButton(title: "Uninstall (\(model.selectedSize.formattedBytes))", module: module,
                                            disabled: model.isRunning(app) || model.files.isEmpty) { confirm = true }
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "app.dashed").font(.system(size: 54)).foregroundStyle(module.accent)
                Text("Pilih aplikasi di kiri untuk melihat semua file miliknya.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
