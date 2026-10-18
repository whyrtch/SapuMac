import SwiftUI
import AppKit
import SapuCore

struct MenuBarLabel: View {
    let monitor: SystemMonitor
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
            if let s = monitor.snapshot { Text("\(Int(s.cpu * 100))%") }
        }
    }
}

struct MenuBarView: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Module.smartScan.accent)
                Text("SapuMac").font(.headline)
                Spacer()
            }
            if let s = monitor.snapshot {
                StatRow(symbol: "cpu", title: "CPU", value: "\(Int(s.cpu * 100))%", fraction: s.cpu, tint: .pink)
                StatRow(symbol: "memorychip", title: "Memori",
                        value: "\(Int64(s.memoryUsed).formattedBytes) / \(Int64(s.memoryTotal).formattedBytes)",
                        fraction: s.memoryFraction, tint: .orange)
                StatRow(symbol: "internaldrive", title: "Disk",
                        value: "\(s.diskFree.formattedBytes) tersisa",
                        fraction: s.diskUsedFraction, tint: s.diskUsedFraction > 0.9 ? .red : .green)
                if let b = s.batteryPercent {
                    StatRow(symbol: s.charging ? "battery.100.bolt" : "battery.75", title: "Baterai",
                            value: "\(b)%\(s.charging ? " · mengisi" : "")", fraction: Double(b) / 100, tint: .blue)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            Divider()
            HStack {
                Button("Buka SapuMac") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("Keluar") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct StatRow: View {
    let symbol: String
    let title: String
    let value: String
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            ProgressView(value: min(max(fraction, 0), 1)).tint(tint)
        }
    }
}
