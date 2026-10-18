import SwiftUI
import SapuCore

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: Module? = .smartScan
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                row(.smartScan)
                Section("Pembersihan") {
                    row(.systemJunk)
                    row(.trash)
                }
                Section("File") { row(.largeFiles) }
                Section("Aplikasi") { row(.uninstaller) }
                Section("Kecepatan") { row(.loginItems) }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            let module = selection ?? .smartScan
            ZStack {
                ModuleBackground(module: module)
                detail(for: module)
                    .padding(28)
            }
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            .animation(.easeInOut(duration: 0.3), value: module)
        }
        .sheet(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            OnboardingView { onboarded = true }
        }
    }

    private func row(_ m: Module) -> some View {
        Label(m.title, systemImage: m.symbol).tag(m)
    }

    @ViewBuilder
    private func detail(for module: Module) -> some View {
        switch module {
        case .smartScan:
            CleanupModuleView(module: .smartScan, model: store.smartScan) { selection = .loginItems }
        case .systemJunk:
            CleanupModuleView(module: .systemJunk, model: store.systemJunk)
        case .trash:
            CleanupModuleView(module: .trash, model: store.trash)
        case .largeFiles:
            LargeFilesView(model: store.largeFiles)
        case .uninstaller:
            UninstallerView(model: store.uninstaller)
        case .loginItems:
            LoginItemsView(model: store.loginItems)
        }
    }
}

/// Banner bila Full Disk Access belum diberikan.
struct FullDiskAccessBanner: View {
    @State private var granted = Permissions.hasFullDiskAccess()

    var body: some View {
        if !granted {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield").font(.title2).foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Disk Access belum aktif").font(.headline)
                    Text("Tanpa izin ini, sebagian cache dan isi Trash tidak bisa dipindai.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Buka Pengaturan") { NSWorkspace.shared.open(Permissions.fullDiskAccessSettingsURL) }
                Button("Periksa lagi") { granted = Permissions.hasFullDiskAccess() }
            }
            .card()
        }
    }
}
