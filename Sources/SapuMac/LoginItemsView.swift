import SwiftUI
import ServiceManagement
import SapuCore

@MainActor @Observable
final class LoginItemsModel {
    let services: Services
    var agents: [LaunchAgent] = []
    var error: String?

    init(services: Services) { self.services = services }

    private var manager: LaunchAgentManager { LaunchAgentManager(locations: services.locations) }

    func load() { agents = manager.list() }

    func set(_ agent: LaunchAgent, enabled: Bool) {
        do {
            try manager.setEnabled(agent, enabled)
        } catch {
            self.error = error.localizedDescription
        }
        load()
    }
}

struct LoginItemsView: View {
    @Bindable var model: LoginItemsModel
    private let module = Module.loginItems

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleHeader(module: module)
            HStack(spacing: 12) {
                Image(systemName: "info.circle").foregroundStyle(module.accent)
                Text("Launch agent di ~/Library/LaunchAgents. Menonaktifkan akan menghentikannya dan menyimpan file-nya, jadi bisa diaktifkan lagi kapan saja.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Login Items macOS…") { SMAppService.openSystemSettingsLoginItems() }
            }
            .card()

            if model.agents.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal").font(.system(size: 48)).foregroundStyle(module.accent)
                    Text("Tidak ada launch agent milik pengguna.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.agents) { agent in
                    HStack(spacing: 12) {
                        Image(systemName: agent.enabled ? "bolt.fill" : "bolt.slash")
                            .foregroundStyle(agent.enabled ? module.accent : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.label).font(.headline)
                            Text(agent.program ?? agent.url.tildePath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { agent.enabled }, set: { model.set(agent, enabled: $0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    .padding(.vertical, 4)
                    .contextMenu { Button("Tampilkan di Finder") { agent.url.revealInFinder() } }
                }
                .scrollContentBackground(.hidden)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear { model.load() }
        .alert("Gagal mengubah launch agent", isPresented: Binding(get: { model.error != nil },
                                                                 set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }
}
