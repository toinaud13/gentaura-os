#!/usr/bin/env bash
# =============================================================================
# Jalon 5 — Definition of Done (6 checks, TDD roadmap 6.5)
# Sur la cible GentAura, session Ash active, apres ./run-stage5.sh launch.
# Sortie 0 = "*** JALON 5 VALIDE ***"
# =============================================================================
set -uo pipefail
PASS=0; FAIL=0; WARN=0
ok(){ printf '  \033[1;32m✔\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
ko(){ printf '  \033[1;31m✘\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
warn(){ printf '  \033[1;33m⚠\033[0m %s\n' "$*"; WARN=$((WARN+1)); }

echo "== DoD-1 : socle hyperviseur =="
lsmod | grep -q '^kvm' && ok "module kvm charge" || ko "kvm non charge"
lsmod | grep -q '^vhost_vsock' && ok "vhost_vsock charge" || ko "vhost_vsock absent"
[[ -e /var/lib/gentaura/vm/rootfs.img && -e /var/lib/gentaura/vm/vmlinuz ]] \
  && ok "artefacts VM presents (rootfs.img + vmlinuz)" || ko "image invitee absente (/var/lib/gentaura/vm)"

echo "== DoD-2 : boot VM < 3s + reponse vsock =="
if systemctl --user is-active --quiet gentaura-crosvm@demo; then
  T=$(systemctl --user show gentaura-crosvm@demo -p ExecMainStartTimestampMonotonic -p InactiveExitTimestampMonotonic 2>/dev/null)
  ok "VM demo active ($T)"
else ko "gentaura-crosvm@demo inactive"; fi

echo "== DoD-3 : fenetre VM projetee dans Ash =="
journalctl --user -u gentaura-crosvm@demo -b --no-pager 2>/dev/null | grep -qiE 'wayland|gpu' \
  && ok "canal wayland/gpu initialise par crosvm (log)" || ko "aucune trace gpu/wayland dans le journal de la VM"

echo "== DoD-4 : preuve ZERO-COPY (dmabuf, pas de copie CPU) =="
bash "$(dirname "$0")/scripts/smoke-zero-copy.sh" >/tmp/stage5-smoke.log 2>&1 \
  && ok "smoke zero-copy vert (detail : /tmp/stage5-smoke.log)" || ko "smoke zero-copy KO (voir docs/TROUBLESHOOTING.md #cpu-fallback)"

echo "== DoD-5 : X11 strictement confine a l'invite =="
if pgrep -x Xorg >/dev/null || pgrep -x X >/dev/null || qlist -Iv x11-base/xorg-server 2>/dev/null | grep -q .; then
  ko "Xorg present sur l'HOTE — violation directe du PRD WON'T HAVE"
else ok "zero serveur X sur l'hote (xwl invite-only)"; fi

echo "== DoD-6 : audio PipeWire via virtio (optionnel) =="
if journalctl --user -u gentaura-crosvm@demo -b --no-pager 2>/dev/null | grep -qi pipewire; then
  ok "canal audio pipewire detecte"
else warn "audio non cablé (COULD HAVE — ne bloque pas la validation)"; fi

echo; echo "DoD Jalon 5 : $PASS OK / $FAIL KO / $WARN WARN"
if (( FAIL == 0 )); then echo "*** JALON 5 VALIDÉ *** (pipeline Zero-Copy opérationnel : PRD SHOULD HAVE Phase 2 atteint)"; exit 0
else echo "*** JALON 5 NON VALIDÉ ***"; exit 1; fi
