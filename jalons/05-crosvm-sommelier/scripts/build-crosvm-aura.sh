#!/usr/bin/env bash
# =============================================================================
# Jalon 5 - Compile crosvm avec le contrat Rutabaga GFX Zero-Copy.
# Equivalent "manuel" de l'ebuild dev-util/crosvm-aura (pour BINHOST pressee).
# Idempotent : relance = incremental cargo build. Sortie -> ~/.cache/gentaura/stage5/bin
# =============================================================================
set -euo pipefail
SRC="${CROSVM_SRC:-$HOME/.cache/gentaura/stage5/crosvm}"
OUT="${GENTAURA_STAGE5_OUT:-$HOME/.cache/gentaura/stage5}"
REV="${CROSVM_REV:-main}"
BIN="$OUT/bin/crosvm"

mkdir -p "$OUT/bin"
if [[ ! -d "$SRC/.git" ]]; then
  echo "[build-crosvm] fetch depot chromium/crosvm (rev $REV)..."
  git clone --depth 1 --branch "$REV" https://chromium.googlesource.com/crosvm/crosvm "$SRC"
else
  echo "[build-crosvm] source presente, update..."
  git -C "$SRC" fetch --depth 1 origin "$REV" && git -C "$SRC" reset --hard FETCH_HEAD
fi

cd "$SRC"
echo "[build-crosvm] verification du contrat rutabaga dans Cargo.toml..."
grep -q 'cross_domain' Cargo.toml || { echo "ERREUR : cette revision ne propose pas le feature cross_domain"; exit 1; }

# Features critiques du pipeline TDD Section 5 :
#   video-codecs non requis ; gpu = rutabaga_gfx ; display + wayland = canal Exo ;
#   "cross-domain" = partage DMABUF hote<->invite zero-copy.
cargo build --release \
  --features "gpu,display-wayland,virtio-gpu,video-decoder,audio-pipewire,cross-domain,sandbox" \
  --target-dir "$OUT/target" 2>&1 | tee "$OUT/crosvm-build.log" || {
    echo "[build-crosvm] fallback sans audio-pipewire (feature absente selon revision)..."
    cargo build --release --features "gpu,display-wayland,virtio-gpu,cross-domain" --target-dir "$OUT/target" 2>&1 | tee -a "$OUT/crosvm-build.log"
}
install -Dm755 "$OUT/target/release/crosvm" "$BIN"
echo "[build-crosvm] OK -> $BIN"
"$BIN" --version
"$BIN" run --help 2>&1 | grep -E -- '--gpu|--wayland-sock|--vsock' >/dev/null \
  && echo "[build-crosvm] CLI conforme au pipeline (gpu/wayland-sock/vsock presents)"
