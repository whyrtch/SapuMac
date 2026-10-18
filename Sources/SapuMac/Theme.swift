import SwiftUI
import AppKit
import SapuCore

enum Module: String, CaseIterable, Identifiable, Hashable {
    case smartScan, systemJunk, trash, largeFiles, uninstaller, loginItems

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: "Smart Scan"
        case .systemJunk: "Sampah Sistem"
        case .trash: "Trash"
        case .largeFiles: "File Besar & Lama"
        case .uninstaller: "Uninstaller"
        case .loginItems: "Login Items"
        }
    }

    var subtitle: String {
        switch self {
        case .smartScan: "Bersihkan Mac dengan sekali klik. Semua file masuk Trash dulu, jadi aman."
        case .systemJunk: "Cache, log, file sementara, dan sampah developer yang menumpuk."
        case .trash: "Kosongkan Trash untuk benar-benar membebaskan ruang."
        case .largeFiles: "Temukan file besar yang sudah lama tidak dibuka."
        case .uninstaller: "Hapus aplikasi beserta seluruh file sisanya."
        case .loginItems: "Atur program yang berjalan otomatis saat login."
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: "sparkles"
        case .systemJunk: "externaldrive.badge.xmark"
        case .trash: "trash"
        case .largeFiles: "doc.richtext"
        case .uninstaller: "app.badge.checkmark"
        case .loginItems: "power"
        }
    }

    var accent: Color {
        switch self {
        case .smartScan: Color(red: 0.98, green: 0.45, blue: 0.75)
        case .systemJunk, .trash: Color(red: 0.25, green: 0.85, blue: 0.62)
        case .largeFiles: Color(red: 0.35, green: 0.65, blue: 1.0)
        case .uninstaller: Color(red: 1.0, green: 0.62, blue: 0.25)
        case .loginItems: Color(red: 1.0, green: 0.42, blue: 0.48)
        }
    }

    var gradient: [Color] {
        switch self {
        case .smartScan: [Color(red: 0.26, green: 0.10, blue: 0.42), Color(red: 0.10, green: 0.12, blue: 0.36)]
        case .systemJunk, .trash: [Color(red: 0.05, green: 0.27, blue: 0.30), Color(red: 0.07, green: 0.12, blue: 0.28)]
        case .largeFiles: [Color(red: 0.07, green: 0.18, blue: 0.42), Color(red: 0.12, green: 0.08, blue: 0.32)]
        case .uninstaller: [Color(red: 0.36, green: 0.16, blue: 0.10), Color(red: 0.20, green: 0.08, blue: 0.26)]
        case .loginItems: [Color(red: 0.38, green: 0.08, blue: 0.20), Color(red: 0.16, green: 0.07, blue: 0.30)]
        }
    }
}

struct ModuleBackground: View {
    let module: Module
    var body: some View {
        LinearGradient(colors: module.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

struct ModuleHeader: View {
    let module: Module
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: module.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(module.accent)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title).font(.title2.bold())
                Text(module.subtitle).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// Tombol bulat besar ala "Scan".
struct BigCircleButton: View {
    let title: String
    let module: Module
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 150, height: 150)
                .background(
                    Circle().fill(LinearGradient(colors: [module.accent, module.accent.opacity(0.55)],
                                                 startPoint: .top, endPoint: .bottom))
                )
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: module.accent.opacity(hover ? 0.8 : 0.45), radius: hover ? 30 : 18)
                .scaleEffect(hover ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hover = h } }
        .accessibilityLabel(title)
    }
}

/// Tombol aksi utama berbentuk kapsul di bawah layar.
struct PrimaryActionButton: View {
    let title: String
    let module: Module
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 36)
                .padding(.vertical, 12)
                .background(Capsule().fill(module.accent.opacity(disabled ? 0.35 : 1)))
                .shadow(color: module.accent.opacity(disabled ? 0 : 0.5), radius: 12)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Cincin progres saat memindai.
struct ScanningView: View {
    let module: Module
    let progress: Double
    let text: String
    let cancel: () -> Void
    @State private var spin = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0.04, progress))
                    .stroke(module.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: progress)
                Image(systemName: module.symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(module.accent)
                    .rotationEffect(.degrees(spin ? 8 : -8))
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: spin)
            }
            .frame(width: 150, height: 150)
            Text(text).font(.headline)
            Button("Batalkan", action: cancel).buttonStyle(.bordered)
        }
        .onAppear { spin = true }
    }
}

/// Kotak centang tiga keadaan untuk kategori.
struct TriCheckbox: View {
    enum State { case all, some, none }
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .all ? "checkmark.square.fill" : state == .some ? "minus.square.fill" : "square")
                .font(.system(size: 16))
                .foregroundStyle(state == .none ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .all ? "Semua dipilih" : state == .some ? "Sebagian dipilih" : "Tidak dipilih")
    }
}

struct FileIcon: View {
    let url: URL
    var size: CGFloat = 20
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

extension URL {
    /// Path dengan ~ untuk home, lebih mudah dibaca.
    var tildePath: String { (path as NSString).abbreviatingWithTildeInPath }

    func revealInFinder() { NSWorkspace.shared.activateFileViewerSelecting([self]) }
}

/// Ringkasan setelah pembersihan.
struct DoneView: View {
    let module: Module
    let report: CleanReport
    let again: () -> Void
    @State private var showFailures = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(module.accent)
                .shadow(color: module.accent.opacity(0.6), radius: 20)
            Text(report.bytes.formattedBytes).font(.system(size: 44, weight: .bold, design: .rounded))
            Text(report.permanentlyDeleted
                 ? "\(report.count) item dibersihkan. Isi Trash dihapus permanen."
                 : "\(report.count) item dipindah ke Trash. Kosongkan Trash untuk membebaskan ruang.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !report.failures.isEmpty {
                Button("\(report.failures.count) item dilewati — lihat alasannya") { showFailures = true }
                    .buttonStyle(.link)
            }
            Button("Selesai", action: again).buttonStyle(.borderedProminent).tint(module.accent)
        }
        .sheet(isPresented: $showFailures) {
            FailureList(failures: report.failures) { showFailures = false }
        }
    }
}

struct FailureList: View {
    let failures: [CleanReport.Failure]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Item yang dilewati").font(.headline)
            Text("Biasanya karena izin macOS (Full Disk Access) atau file sedang dipakai.")
                .font(.callout).foregroundStyle(.secondary)
            List(failures) { f in
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.url.tildePath).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    Text(f.reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 240)
            HStack { Spacer(); Button("Tutup", action: close).keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 560, height: 380)
    }
}
