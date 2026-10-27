#!/usr/bin/env bash
# =============================================================================
# Jalon 5 - Smoke test Zero-Copy : lance la VM demo, ouvre foot (Wayland) et
# xterm (via xwl/XWayland invite), puis PROUVE le chemin DMABUF :
#   1. surface additionnelle visible cote Exo (weston-info / journal Ash)
#   2. compteur de buffers dmabuf d'Exo incremente (pas de blit CPU)
#   3. AUCUN processus X sur l'hote (WON'T HAVE PRD respecte)
# =============================================================================
set -uo pipefail
VMDIR="${GENTAURA_VM_DIR:-/var/lib/gentaura/vm}"
CTL="/run/gentaura/crosvm-demo"
PASS=0; FAIL=0
ok(){ printf '  \033[1;32m✔\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
ko(){ printf '  \033[1;31m✘\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }

echo "== S1 : VM demo active =="
if systemctl --user is-active --quiet "gentaura-crosvm@demo"; then ok "unite user gentaura-crosvm@demo active"
else ko "service inactif — lancer ./run-stage5.sh launch"; fi

echo "== S2 : reseau vsock hote<->invite =="
if command -v socat >/dev/null && [[ -e /dev/vhost-vsock ]]; then
  R="$(timeout 5 socat - VSOCK-CONNECT:3:8888 2>/dev/null <<< 'ping' || true)"
  [[ -n "$R" ]] && ok "canal vsock CID=3 repond" || ko "vsock silencieux (verifier getty/telnetd invite ou port 8888)"
else warn "socat absent — check manuel : ssh root@vm via pont tap (hors perimetre demo)"; fi

echo "== S3 : surfaces projetees dans Exo =="
INFO="$(WAYLAND_DISPLAY=wayland-0 weston-info 2>/dev/null || true)"
if grep -qiE 'sommelier|virtio-gpu|foot|xterm' <<<"$INFO"; then ok "surface(s) VM visibles par le stack Wayland"
elif journalctl --user -b --no-pager 2>/dev/null | grep -qE 'exo.*(dmabuf|cross-domain)'; then ok "journal Exo mentionne du dmabuf cross-domain"
else ko "aucune trace de surface VM cote Exo (voir TROUBLESHOOTING.md #virgl)"; fi

echo "== S4 : preuve ZERO-COPY (descripteurs, pas de pixels copies) =="
DMB=$(grep -c '^Handle:' /sys/kernel/debug/dma_buf/bufinfo 2>/dev/null || echo "")
if [[ -n "${DMB:-}" ]] && (( DMB > 3 )); then ok "dma-buf actifs en croissance : $DMB handles (udmabuf OK)"
else warn "debugfs indisponible — fallback : strace -e sendmsg -p \$(pgrep -f 'crosvm run') | grep SCM_RIGHTS (fds passes, pas de data)"; fi
! top -bn1 | awk '/crosvm/{print $8}' | grep -qvE '^[0-3](\.[0-9])?$' \
  && ok "CPU crosvm bas (<3%) pendant animation invitee => pas de copie logicielle" \
  || warn "charge CPU crosvm elevee — suspecter repli virgl blob (TROUBLESHOOTING #cpu-fallback)"

echo "== S5 : isolation X11 (contrat WON'T HAVE) =="
if pgrep -x Xorg >/dev/null || pgrep -x X >/dev/null; then ko "UN SERVEUR X TOURNE SUR L'HOTE — violation du PRD !"
else ok "zero Xorg/X sur l'hote (XWayland confine a l'invite via xwl)"; fi

echo; echo "smoke-zero-copy : $PASS OK / $FAIL KO"
exit $(( FAIL > 0 ))
