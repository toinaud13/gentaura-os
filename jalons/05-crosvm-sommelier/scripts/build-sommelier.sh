#!/usr/bin/env bash
# =============================================================================
# Jalon 5 - Build de sommelier (proxy Wayland/X11 invite) + xwl.
# Source : depot cros-systems/sommelier. Binaire injecte ensuite dans l'image
# invitee par stage5-image.sh (etape "image").
# =============================================================================
set -euo pipefail
SRC="${SOMMELIER_SRC:-$HOME/.cache/gentaura/stage5/sommelier}"
OUT="${GENTAURA_STAGE5_OUT:-$HOME/.cache/gentaura/stage5}"
PREFIX="$OUT/sysroot-vm"
mkdir -p "$OUT"

if [[ ! -d "$SRC/.git" ]]; then
  echo "[build-sommelier] fetch cros-systems/sommelier..."
  git clone --depth 1 https://chromium.googlesource.com/cros-systems/sommelier "$SRC"
fi
cd "$SRC"
if [[ -f configure.ac || -d .git && -f autogen.sh ]]; then
  # Branche autotools (historique) :
  ./autogen.sh
  PKG_CONFIG_PATH="$PREFIX/usr/lib/pkgconfig" \
  ./configure --prefix=/usr --enable-xwl --disable-static
  make -j"$(nproc)" && make install DESTDIR="$PREFIX"
else
  # Variante meson des revisions recentes :
  rm -rf build && meson setup build --prefix=/usr -Dxwl=true --cross-file "${SOMMELIER_CROSS:-/dev/null}" 2>/dev/null \
    || meson setup build --prefix=/usr -Dxwl=true
  ninja -C build && DESTDIR="$PREFIX" ninja -C build install
fi
test -x "$PREFIX/usr/bin/sommelier" && echo "[build-sommelier] OK -> $PREFIX/usr/bin/sommelier"
test -x "$PREFIX/usr/bin/xwl"       && echo "[build-sommelier] xwl (XWayland invite) -> $PREFIX/usr/bin/xwl"
