#!/usr/bin/env bash
# =============================================================================
# Jalon 5 — Hyperviseur graphique crosvm + Sommelier (Phase 2)
# Orchestrateur idempotent : check -> build -> image -> install -> launch -> smoke
# Relançable après toute interruption. Sous-étapes exécutables séparément.
# =============================================================================
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$STAGE_DIR"
OUT="${GENTAURA_STAGE5_OUT:-$HOME/.cache/gentaura/stage5}"

log(){ printf '\n\033[1;36m[stage5]\033[0m %s\n' "$*"; }

step_check()   { log "Pré-vol noyau Phase 2 / droits / outils"; bash scripts/check-kernel-config.sh; }
step_build()   { log "Build crosvm (rutabaga cross-domain) puis sommelier"; bash scripts/build-crosvm-aura.sh && bash scripts/build-sommelier.sh; }
step_image()   { log "Construction de l'image invitée (rootfs + vmlinuz)"; bash scripts/stage5-image.sh; }
step_install() { log "udev rules + groupes kvm/vhost/render + unités user"; sudo bash scripts/install-udev-rules.sh
                 mkdir -p ~/.config/systemd/user
                 install -m644 systemd/gentaura-crosvm@.service ~/.config/systemd/user/
                 systemctl --user daemon-reload; }
step_launch()  { log "Démarrage de la VM demo"; systemctl --user start gentaura-crosvm@demo
                 for i in $(seq 1 30); do systemctl --user is-active --quiet gentaura-crosvm@demo && break; sleep 1; done
                 journalctl --user -u gentaura-crosvm@demo -b --no-pager | tail -20; }
step_smoke()   { log "Smoke test zero-copy"; bash scripts/smoke-zero-copy.sh; }

case "${1:-all}" in
  check)   step_check ;;
  build)   step_build ;;
  image)   step_image ;;
  install) step_install ;;
  launch)  step_launch ;;
  smoke)   step_smoke ;;
  all)     step_check; step_build; step_image; step_install; step_launch; step_smoke ;;
  *)       echo "usage: $0 {check|build|image|install|launch|smoke|all}"; exit 1 ;;
esac
log "run-stage5 ($1) terminé."
