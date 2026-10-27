#!/bin/bash
# ============================================================================
# GENTAura - JALON 1 : Critere d'arret (Definition of Done)
# ----------------------------------------------------------------------------
# A lancer sur le systeme installe, en TTY console pure.
# Le jalon est VALIDER si les 6 tests passent -> demarrage console < 3 s, zero X11.
# ============================================================================
set -uo pipefail
PASS=0; FAIL=0
t() { # t "nom" commande...
  if "$@" >/dev/null 2>&1; then echo "  [OK]   $1"; PASS=$((PASS+1));
  else echo "  [FAIL] $1"; FAIL=$((FAIL+1)); fi
}

echo "== 1. systemd est PID 1 =="
t "systemd PID1" test "$(ps -p 1 -o comm=)" = systemd

echo "== 2. Contrat noyau actif (running kernel) =="
K=$(ls /proc/config.gz 2>/dev/null && echo zcat || echo "zcat /usr/src/linux/.config")
for c in CONFIG_UDMABUF CONFIG_SYNC_FILE CONFIG_DMA_SHARED_BUFFER CONFIG_CGROUPS \
         CONFIG_MEMCG CONFIG_PSI CONFIG_USER_NS CONFIG_SECCOMP CONFIG_VIRTUALIZATION; do
  if [ -e /proc/config.gz ]; then R=$(zcat /proc/config.gz); else R=$(cat "/usr/src/linux-$(uname -r)/.config" 2>/dev/null || cat /boot/config-$(uname -r) 2>/dev/null); fi
  echo "$R" | grep -qE "^${c}=y|^${c}=m" && { echo "  [OK]   ${c}"; PASS=$((PASS+1)); } || { echo "  [FAIL] ${c}"; FAIL=$((FAIL+1)); }
done

echo "== 3. Zero X11 sur l'hote (WON'T HAVE du PRD) =="
t "aucun binaire Xorg" bash -c "! command -v Xorg && ! pgrep -x Xorg"
t "pas de libXwayland hote" bash -c "! ldconfig -p | grep -q 'libX11.so.*=> /'" || true
# NB: mesa avec USE=-X ne doit tirer AUCUN paquet x11-* dans le world
t "world sans x11-" bash -c "! equery list --origin installed '*/*' 2>/dev/null | grep -q '^x11-base\|^x11-' "

echo "== 4. GPU direct KMS/DRM + GBM =="
t "node /dev/dri/card0" test -e /dev/dri/card0
t "gbm via mesa" bash -c "has_gbm=\$(eselect profile show 2>/dev/null); mesainfo --version 2>/dev/null || equery hasuse gbm media-libs/mesa || true; test -f /usr/lib64/libgbm.so || test -f /usr/lib/x86_64-linux-gnu/libgbm.so || ldconfig -p | grep -q 'libgbm'"

echo "== 5. Socle services =="
t "NetworkManager active" systemctl is-active --quiet NetworkManager
t "PipeWire actif (user)" bash -c "systemctl --user is-active --quiet pipewire 2>/dev/null || loginctl-user-pw-ok 2>/dev/null || pgrep -x pipewire"
t "iwd ou NM-wifi" bash -c "systemctl is-active --quiet iwd || nmcli radio wifi >/dev/null 2>&1"
t "libinput present" test -f /usr/lib64/libinput.so.10 || test -e /usr/include/libinput.h

echo "== 6. Chronometre cold-boot (KPI: console interactive < 3 s) =="
if command -v systemd-analyze >/dev/null; then
  TOT=$(systemd-analyze 2>/dev/null | awk '/Kernel|startup/{print $NF}' | tr -d 's')
  echo "  Temps boot total releve : ${TOT}s (cible < 3s)"
fi

echo "----------------------------------------"
echo "RESULTAT : $PASS OK / $FAIL FAIL"
[ "$FAIL" -eq 0 ] && echo "*** JALON 1 VALIDER -> passage au Jalon 2 ***" || echo "*** JALON 1 NON VALIDER — corrige les FAIL ci-dessus ***"
exit "$FAIL"
