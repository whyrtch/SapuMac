import Foundation

public struct LaunchAgent: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let label: String
    public let program: String?
    public let enabled: Bool
}

/// Launch agent milik pengguna (~/Library/LaunchAgents). Menonaktifkan = unload + pindahkan plist
/// ke folder SapuMac, sehingga bisa diaktifkan kembali kapan saja.
public struct LaunchAgentManager: Sendable {
    public let locations: Locations

    public init(locations: Locations = Locations()) {
        self.locations = locations
    }

    public var activeDir: URL { locations.lib("LaunchAgents") }
    public var disabledDir: URL { locations.sapuSupportDir.appendingPathComponent("DisabledLaunchAgents") }

    public func list() -> [LaunchAgent] {
        (read(activeDir, enabled: true) + read(disabledDir, enabled: false))
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    public func setEnabled(_ agent: LaunchAgent, _ enabled: Bool) throws {
        guard agent.enabled != enabled else { return }
        let fm = FileManager.default
        let name = agent.url.lastPathComponent
        if enabled {
            let dest = activeDir.appendingPathComponent(name)
            try fm.moveItem(at: agent.url, to: dest)
            launchctl(["bootstrap", "gui/\(getuid())", dest.path])
        } else {
            launchctl(["bootout", "gui/\(getuid())", agent.url.path])
            try fm.createDirectory(at: disabledDir, withIntermediateDirectories: true)
            try fm.moveItem(at: agent.url, to: disabledDir.appendingPathComponent(name))
        }
    }

    func read(_ dir: URL, enabled: Bool) -> [LaunchAgent] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension == "plist" }.map { url in
            let dict = NSDictionary(contentsOf: url) as? [String: Any] ?? [:]
            let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
            return LaunchAgent(url: url,
                               label: dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent,
                               program: program, enabled: enabled)
        }
    }

    @discardableResult
    func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
