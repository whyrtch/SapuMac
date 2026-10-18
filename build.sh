#!/bin/zsh
# Build SapuMac.app (release) ke folder build/.
# Pemakaian: ./build.sh            -> build saja
#            ./build.sh --install  -> build lalu salin ke ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/SapuMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SapuMac "$APP/Contents/MacOS/SapuMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Signing ad-hoc: cukup untuk pemakaian pribadi di Mac sendiri.
codesign --force --deep --sign - "$APP"
echo "Selesai: $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/SapuMac.app
    cp -R "$APP" ~/Applications/
    echo "Terpasang di ~/Applications/SapuMac.app"
fi
