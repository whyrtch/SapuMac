# SapuMac

Aplikasi pembersih macOS untuk pemakaian pribadi (Swift 6 + SwiftUI, macOS 14+).

## Build & jalankan

```bash
./build.sh             # menghasilkan build/SapuMac.app
./build.sh --install   # build lalu salin ke ~/Applications
swift test             # uji keamanan penghapusan & scanner
```

Setelah dipasang, beri **Full Disk Access** ke SapuMac (System Settings → Privacy & Security).
Karena app di-sign ad-hoc, izin ini mungkin perlu diberikan ulang setelah build baru.

## Fitur MVP

| Modul | Isi |
| --- | --- |
| Smart Scan | Sampah sistem + sampah developer + Trash + jumlah launch agent, sekali klik |
| Sampah Sistem | Cache, log, laporan crash, file temp > 24 jam, DerivedData, cache Simulator, npm/Yarn/pnpm/pip/Homebrew, Archives, DeviceSupport |
| Trash | Lihat & kosongkan Trash (permanen, dengan konfirmasi) |
| File Besar & Lama | File ≥ 50 MB di home (tanpa ~/Library), filter ukuran/umur/jenis |
| Uninstaller | Aplikasi + file sisa di ~/Library (aplikasi Apple disembunyikan) |
| Login Items | Aktif/nonaktifkan launch agent di ~/Library/LaunchAgents |
| Menu bar | CPU, memori, disk, baterai |

## Keamanan

Semua penghapusan lewat `SafetyGuard` (`Sources/SapuCore/SafetyGuard.swift`):

- Pembersihan otomatis hanya di allowlist; symlink dan `..` di-resolve dulu.
- Documents, Desktop, Keychains, iCloud Drive, Mail, Messages, Photos Library, dan folder sistem dilindungi.
- File masuk Trash (`trashItem`); hanya "Kosongkan Trash" yang menghapus permanen.
- Cache Apple (`com.apple.*`) dan cache aplikasi yang sedang berjalan dilewati.
- Log setiap aksi: `~/Library/Logs/SapuMac/cleanup.log`.

## Struktur

```
Sources/SapuCore   logika: scanner, SafetyGuard, Cleaner, SystemSampler (tanpa UI)
Sources/SapuMac    SwiftUI: sidebar, modul, menu bar, onboarding
Tests/             Swift Testing, pakai home palsu di folder sementara
scripts/           make-icon.swift (membuat Resources/AppIcon.icns)
```
