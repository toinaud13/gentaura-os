#!/usr/bin/env bash
# ============================================================================
# GentAura - Jalon 2 : vérification PRÉ-COMPILATION de la machine BINHOST/dev
# Valide les exigences du stress-test final (RAM / swap / disque / noyau).
# Sortie 0 = prêt à compiler. Chaque échec indique la remédiation.
# ============================================================================
set -uo pipefail
FAIL=0
ok()   { echo "  [OK]   $1"; }
ko()   { echo "  [KO]   $1" ; FAIL=1; }

echo "== GentAura Jalon 2 : pré-vol de la machine de build =="

# --- RAM + swap >= 32 Go effectifs (contrat linking lld) ---
ram_gb=$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo)
swap_gb=$(awk '/SwapTotal/{print int($2/1024/1024)}' /proc/meminfo)
total=$((ram_gb + swap_gb))
if (( ram_gb >= 32 )); then ok "RAM physique ${ram_gb} Go (>= 32 Go)"
elif (( total >= 48 )) && lsblk -d -o NAME,TYPE 2>/dev/null | grep -q zram; then
  ok "RAM ${ram_gb} Go + swap ${swap_gb} Go avec ZRAM détecté (acceptable si NVMe rapide)"
elif (( total >= 48 )); then
  ok "RAM ${ram_gb} Go + swap ${swap_gb} Go (marche si swap sur NVMe, lent sinon)"
else
  ko "Mémoire insuffisante (${ram_gb}+${swap_gb} Go < 48) -> activer ZRAM :"
  echo "         emerge -au sys-apps/zram-tools && zramctl /dev/zram0 --size 32G --algorithm zstd && swapon /dev/zram0"
fi

# --- Disque /var/tmp/portage (ou équivalent build) >= 80 Go libres ---
BUILD_DISK="${PORTAGE_TMPDIR:-/var/tmp}/portage"
mkdir -p "$BUILD_DISK" 2>/dev/null || BUILD_DISK=/var/tmp
free_gb=$(df -BG --output=avail "$BUILD_DISK" 2>/dev/null | tail -1 | tr -dc '0-9')
if (( ${free_gb:-0} >= 80 )); then ok "$BUILD_DISK : ${free_gb} Go libres (>= 80 Go)"
else ko "$BUILD_DIR_PLACEHOLDER : ${free_gb:-?} Go libres < 80 Go -> monter un disque dédié sur /var/tmp/portage"; fi

# --- Checkout Chromium >= 100 Go si déjà fetché ---
SRC="${CHROMIUM_SRC:-$HOME/gentaura-build/src}"
if [[ -d "$SRC" ]]; then
  size_gb=$(du -sBG "$SRC" 2>/dev/null | cut -f1 | tr -dc '0-9')
  ok "Checkout présent : $SRC (${size_gb} Go)"
else
  echo "  [INFO] Pas encore de checkout ($SRC) — normal avant 'fetch'."
fi

# --- Contrat noyau minimal pour le sandbox + tests Exo ---
K="/proc/config.gz"; [[ -f $K ]] || K="/lib/modules/$(uname -r)/.config"
if [[ -f $K ]]; then
  for opt in CONFIG_USER_NS CONFIG_SECCOMP CONFIG_CGROUPS CONFIG_DMA_SHARED_BUFFER; do
    if grep -qE "^$opt=[ym]" "$K" 2>/dev/null || \
       (zgrep -qE "^$opt=[ym]" "$K" 2>/dev/null); then ok "$opt"; else
      ko "$opt absent du noyau (sandbox Chromium / dma-buf impossible)"; fi
  done
else
  echo "  [INFO] /proc/config.gz indisponible — vérifier le contrat kernel/gentaura.config manuellement."
fi

# --- Outils ---
for t in git ninja gn python3 patch curl; do
  command -v "$t" >/dev/null && ok "binaire '$t'" || ko "'$t' manquant (depot_tools ou emerge)"
done

# --- CPU ---
n=$(nproc)
(( n >= 8 )) && ok "$n cœurs CPU" || echo "  [WARN] $n cœurs : compilation estimée > 12 h"

echo "=============================================="
if (( FAIL )); then echo "*** PRÉ-VOL JALON 2 ÉCHOUÉ — corriger les [KO] ci-dessus ***"; exit 1
else echo "*** PRÉ-VOL JALON 2 OK — lancer : run-stage2-build.sh all ***"; fi
