#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.0.0}"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
BUNDLE_DIR="build/linux/x64/release/bundle"

if [ ! -d "$BUNDLE_DIR" ]; then
  BUNDLE_DIR="build/linux/arm64/release/bundle"
fi

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "Linux release bundle not found. Run: flutter build linux --release"
  exit 1
fi

PKG_ROOT="build/deb/luch_${VERSION}_${ARCH}"
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/DEBIAN"
mkdir -p "$PKG_ROOT/opt/luch"
mkdir -p "$PKG_ROOT/usr/local/bin"
mkdir -p "$PKG_ROOT/usr/share/applications"

cp -r "$BUNDLE_DIR"/* "$PKG_ROOT/opt/luch/"
chmod +x "$PKG_ROOT/opt/luch/luch"

cat > "$PKG_ROOT/usr/local/bin/luch" << 'EOF'
#!/usr/bin/env bash
exec /opt/luch/luch "$@"
EOF
chmod +x "$PKG_ROOT/usr/local/bin/luch"

cat > "$PKG_ROOT/usr/share/applications/luch.desktop" << 'EOF'
[Desktop Entry]
Name=Луч (Luch)
Comment=Обмен файлами между устройствами по QR-коду в локальной сети
Exec=/opt/luch/luch
Terminal=false
Type=Application
Categories=Utility;Network;FileTransfer;
StartupNotify=true
EOF

cat > "$PKG_ROOT/DEBIAN/control" << EOF
Package: luch
Version: ${VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Depends: libgtk-3-0, libblkid1, liblzma5
Maintainer: Luch Team <support@luch.app>
Description: Luch — кроссплатформенный обмен файлами по QR-коду
 Локальная передача файлов между Android, iOS, Windows и Linux через QR-код.
EOF

dpkg-deb --build "$PKG_ROOT" "build/deb/luch_${VERSION}_${ARCH}.deb"
echo "Created build/deb/luch_${VERSION}_${ARCH}.deb"
