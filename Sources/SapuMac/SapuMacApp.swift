import SwiftUI
import SapuCore

@main
struct SapuMacApp: App {
    @State private var store = AppStore()
    @State private var monitor = SystemMonitor()

    var body: some Scene {
        WindowGroup("SapuMac", id: "main") {
            ContentView()
                .environment(store)
                .environment(monitor)
                .frame(minWidth: 980, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 700)

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuBarView().environment(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Layanan bersama: satu SafetyGuard dan satu Cleaner untuk seluruh app.
struct Services: Sendable {
    let locations = Locations()
    var safety: SafetyGuard { SafetyGuard(locations: locations) }
    var cleaner: Cleaner { Cleaner(safety: safety, log: CleanupLog(locations: locations)) }
}

@MainActor @Observable
final class AppStore {
    let services = Services()
    let smartScan: CleanupModel
    let systemJunk: CleanupModel
    let trash: CleanupModel
    let largeFiles: LargeFilesModel
    let uninstaller: UninstallerModel
    let loginItems: LoginItemsModel

    init() {
        smartScan = CleanupModel(kind: .smart, services: services)
        systemJunk = CleanupModel(kind: .junk, services: services)
        trash = CleanupModel(kind: .trash, services: services)
        largeFiles = LargeFilesModel(services: services)
        uninstaller = UninstallerModel(services: services)
        loginItems = LoginItemsModel(services: services)
    }
}

@MainActor @Observable
final class SystemMonitor {
    var snapshot: SystemSnapshot?
    private let sampler = SystemSampler()

    init() {
        _ = sampler.sample() // sampel awal untuk selisih CPU
        Task { [weak self] in
            while let self {
                self.snapshot = self.sampler.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
