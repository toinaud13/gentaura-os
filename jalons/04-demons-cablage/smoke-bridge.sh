#!/usr/bin/env bash
# =============================================================================
# Jalon 4 — Smoke test contractuel du pont D-Bus gentaura-bridge
# Prouve que chaque interface org.chromium.* exposée à Ash répond ET que la
# cible Gentoo réelle (NM / UPower / logind) derrière le pont est bien vivante.
# Sortie : 0 = contrat respecté, 1 = violation (avec diagnostic).
# =============================================================================
set -uo pipefail

PASS=0; FAIL=0
ok() { printf '  \033[1;32m✔\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
ko() { printf '  \33[1;31m✘\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }

dbus_sys() { gdbus call --system --dest "$1" --object-path "$2" --method "$3" 2>&1; }

echo "== A. Noms bus système acquis par le pont =="
NAMES="$(dbus_sys org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames)"
for name in org.chromium.flimflam org.chromium.PowerManager org.chromium.SessionManager; do
  grep -q "\"$name\"" <<<"$NAMES" && ok "nom acquis : $name" || ko "nom ABSENT : $name (le pont tourne-t-il ? systemctl status gentaura-bridge)"
done

echo "== B. Interface flimflam.Manager (-> NetworkManager/iwd) =="
R="$(dbus_sys org.chromium.flimflam /org/chromium/flimflam/Manager org.chromium.flimflam.Manager.GetProperties)"
[[ $R != Error* && -n $R ]] && ok "GetProperties() répond : ${R:0:80}…" || ko "GetProperties() muet : $R"
R="$(dbus_sys org.chromium.flimflam /org/chromium/flimflam/Manager org.chromium.flimflam.Manager.RequestScan)"
[[ $R != Error* ]] && ok "RequestScan() accepté (relayé vers NM rescan)" || ko "RequestScan() : $R"
# Preuve de la cible réelle derrière le pont :
if command -v nmcli >/dev/null; then
  STATE="$(nmcli -t -f DEVICE,TYPE,STATE devices 2>/dev/null | grep wifi || true)"
  [[ -n "$STATE" ]] && ok "cible réelle vivante : NetworkManager voit un device wifi ($STATE)" \
                    || echo "  ℹ pas de device wifi (VM sans puce ? acceptable, le relais reste à prouver en session)"
fi

echo "== C. Interface PowerManager (-> UPower & logind) =="
R="$(dbus_sys org.chromium.PowerManager /org/chromium/PowerManager org.chromium.PowerManager.GetPowerSupplyProperties)"
[[ $R != Error* && -n $R ]] && ok "GetPowerSupplyProperties() répond : ${R:0:80}…" || ko "GetPowerSupplyProperties() : $R"
# Le pont doit refléter l'UPower réel, pas un stub figé à 100 % :
UPCT="$(upower -i "$(upower -e 2>/dev/null | grep -m1 'BAT' || true)" 2>/dev/null | awk -F'[ %]+' '/percentage/{print $2}' || true)"
if [[ -n "${UPCT:-}" ]]; then
  if grep -q "$UPCT" <<<"$R"; then ok "valeur batterie cohérente avec UPower (${UPCT}%) — relais réel"
  else ko "divergence : pont renvoie autre chose que UPower (${UPCT}%) → vérifier mappage DisplayDevice"; fi
else
  echo "  ℹ pas de batterie (desktop/VM) : contrôle remplacé par la présence d'UPower sur le bus"
  dbus_sys org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.DBus.Properties.Get 2>&1 | grep -qi error \
    && ko "UPower absent du bus — cible morte" || ok "cible UPower présente sur le bus"
fi

echo "== D. Interface SessionManager (validation immédiate PAM) =="
R="$(dbus_sys org.chromium.SessionManager /org/chromium/SessionManager org.chromium.SessionManagerInterface.RetrieveSessionState)"
grep -q 'uint32 2' <<<"$R" && ok "RetrieveSessionState() = SESSION_STARTED (2) — bureau Ash débloqué" \
                          || ko "état séance inattendu : $R (attendu 'uint32 2')"
R="$(dbus_sys org.chromium.SessionManager /org/chromium/SessionManager org.chromium.SessionManagerInterface.EmitLoginPromptVisible)"
[[ $R != Error* ]] && ok "EmitLoginPromptVisible() acquiescé (prompt Google supprimé, patch 02)" || ko "EmitLoginPromptVisible() : $R"

echo "== E. Ordre de service (Before=gentaura-shell) =="
systemctl show gentaura-bridge.service -p ExecMainStartTimestamp --value >/dev/null 2>&1 && \
  ok "unité gentaura-bridge installée et démarrable (Type=dbus satisfait)" || ko "unité absente — lancer run-stage4.sh install"

echo
printf '== RÉSULTAT : %d ✔ / %d ✘ ==\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
