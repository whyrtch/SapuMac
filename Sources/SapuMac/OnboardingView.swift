import SwiftUI
import AppKit
import SapuCore

/// Tiga langkah: sambutan → izin Full Disk Access → mulai.
struct OnboardingView: View {
    let finish: () -> Void
    @State private var step = 0
    @State private var hasAccess = Permissions.hasFullDiskAccess()

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            switch step {
            case 0:
                icon("sparkles", .smartScan)
                Text("Selamat datang di SapuMac").font(.largeTitle.bold())
                Text("Bersihkan file sampah, temukan file besar, dan hapus aplikasi sampai tuntas.\nSemua yang dihapus masuk Trash dulu, jadi aman.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            case 1:
                icon(hasAccess ? "lock.open" : "lock.shield", .largeFiles)
                Text("Beri izin Full Disk Access").font(.title.bold())
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Klik **Buka Pengaturan** di bawah.")
                    Text("2. Aktifkan **SapuMac** di daftar Full Disk Access (klik + bila belum ada).")
                    Text("3. Kembali ke sini dan klik **Periksa lagi**.")
                }
                .foregroundStyle(.secondary)
                HStack {
                    Button("Buka Pengaturan") { NSWorkspace.shared.open(Permissions.fullDiskAccessSettingsURL) }
                    Button("Periksa lagi") { hasAccess = Permissions.hasFullDiskAccess() }
                }
                Label(hasAccess ? "Izin aktif" : "Belum aktif — SapuMac tetap bisa dipakai secara terbatas",
                      systemImage: hasAccess ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(hasAccess ? .green : .orange)
            default:
                icon("checkmark.seal", .systemJunk)
                Text("Siap!").font(.largeTitle.bold())
                Text("Tekan Scan di Smart Scan untuk pembersihan pertama Anda.").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack {
                if step > 0 { Button("Kembali") { step -= 1 } }
                Spacer()
                Button(step < 2 ? "Lanjut" : "Mulai") { if step < 2 { step += 1 } else { finish() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 560, height: 440)
    }

    private func icon(_ name: String, _ m: Module) -> some View {
        Image(systemName: name)
            .font(.system(size: 52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 96, height: 96)
            .background(LinearGradient(colors: [m.accent, m.gradient[0]], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 24))
    }
}

struct SettingsView: View {
    @AppStorage("largeMinMB") private var largeMinMB = 100
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        Form {
            Picker("Ukuran minimum File Besar", selection: $largeMinMB) {
                ForEach(LargeFilesModel.sizeOptions, id: \.self) { mb in
                    Text(mb >= 1000 ? "\(mb / 1000) GB" : "\(mb) MB").tag(mb)
                }
            }
            LabeledContent("Log pembersihan") {
                Button("Tampilkan di Finder") {
                    let log = CleanupLog().file
                    let target = FileManager.default.fileExists(atPath: log.path) ? log : log.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
                    target.revealInFinder()
                }
            }
            LabeledContent("Panduan awal") {
                Button("Tampilkan lagi") { onboarded = false }
            }
            LabeledContent("Full Disk Access") {
                Button("Buka Pengaturan") { NSWorkspace.shared.open(Permissions.fullDiskAccessSettingsURL) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 260)
    }
}
