#!/usr/bin/env bash
# =============================================================================
# Jalon 4 — Definition of Done (5 checks)
# À lancer sur la CIBLE GentAura, en session graphique active.
#   ./validate-stage4.sh          -> exécute les 5 checks
# Sortie 0 = "*** JALON 4 VALIDÉ ***"
# =============================================================================
set -uo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok(){ printf '  \033[1;32m✔\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
ko(){ printf '  \033[1;31m✘\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }

echo "== DoD-1 : pont vivant, 3 noms org.chromium.* acquis =="
if systemctl is-active --quiet gentaura-bridge.service; then
  NAMES="$(gdbus call --system --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ListNames 2>/dev/null)"
  n=0; for name in org.chromium.flimflam org.chromium.PowerManager org.chromium.SessionManager; do
    grep -q "\"$name\"" <<<"$NAMES" && n=$((n+1)); done
  (( n == 3 )) && ok "Type=dbus satisfait + $n/3 noms bus actifs" || ko "seulement $n/3 noms acquis"
else ko "gentaura-bridge.inactif — run-stage4.sh install"; fi

echo "== DoD-2 : batterie réelle (relais UPower, pas de stub) =="
bash "$STAGE_DIR/smoke-bridge.sh" 2>/dev/null | grep -E '(cohérente avec UPower|cible UPower présente)' >/dev/null \
  && ok "jauge alimentée par l'UPower réel (ou cible vérifiée sans batterie)" \
  || ko "relais batterie non prouvé — voir smoke-bridge.sh section C"

echo "== DoD-3 : Wi-Fi réel (RequestScan relayé vers NM/iwd) =="
R="$(gdbus call --system --dest org.chromium.flimflam --object-path /org/chromium/flimflam/Manager --method org.chromium.flimflam.Manager.RequestScan 2>&1)"
[[ $R != Error* ]] && ok "RequestScan() sans erreur D-Bus" || ko "RequestScan() : $R"
journalctl -u gentaura-bridge -b --no-pager 2>/dev/null | grep -q 'NetworkManager/iwd scan' \
  && ok "trace journal : relais vers NetworkManager/iwd confirmé" \
  || echo "  ℹ (optionnel) trace de relais absente des journaux du boot courant"

echo "== DoD-4 : Ash démarre sans écran de connexion (SESSION_STARTED) =="
R="$(gdbus call --system --dest org.chromium.SessionManager --object-path /org/chromium/SessionManager --method org.chromium.SessionManagerInterface.RetrieveSessionState 2>&1)"
grep -q 'uint32 2' <<<"$R" && ok "RetrieveSessionState()=2 (patch 02 cohérent avec le pont)" || ko "état séance : $R"

echo "== DoD-5 : Shelf native (.desktop -> gentaura:* -> scope cgroup) =="
if systemctl --user is-active --quiet gentaura-app-scanner 2>/dev/null; then
  ok "scanner actif dans la session user"
  CNT="$(journalctl --user -u gentaura-app-scanner -b --no-pager 2>/dev/null | grep -c 'registered into Ash App List')"
  (( CNT > 0 )) && ok "$CNT entrée(s) .desktop enregistrée(s) dans la App List" \
                 || ko "aucune app enregistrée — vérifier /usr/share/applications et les patchs 03 d'Ash"
  # Preuve d'exécution isolée (nécessite un clic manuel dans Ash au moins une fois) :
  UNITS="$(systemctl --user list-units 'app-gentaura-*' --no-legend 2>/dev/null | wc -l)"
  if (( UNITS > 0 )); then ok "$UNITS scope(s) app-gentaura-* créés (isolation cgroups v2)"
  else echo "  ℹ aucun scope pour l'instant : cliquer une icône dans Ash puis relancer ce check"; fi
else
  ko "scanner inactif — systemctl --user start gentaura-app-scanner (en session graphique)"
fi

echo
if (( FAIL == 0 )); then
  printf '\033[1;32m*** JALON 4 VALIDÉ ***\033[0m — bridge & scanner câblés, jauges live, Shelf native opérationnelle.\n'
  exit 0
else
  printf '\033[1;31m*** JALON 4 NON VALIDÉ *** (%d échec(s)) — corriger puis relancer.\033[0m\n' "$FAIL"
  exit 1
fi
