#!/bin/bash
# ============================================================================
# GentAura - Serveur BINHOST (Jalon 2/3, "Point de vigilance" du stress-test)
# La compilation de chromium-ash exige >=32 Go RAM (lld) + ~80 Go disque.
# On compile UNIQUEMENT sur la machine puissante ; les machines cibles
# GentAura telechargent le .gpkg.tar pret a l'emploi en quelques secondes.
# ============================================================================
set -eu

BINHOST_DIR="${BINHOST_DIR:-/var/cache/binhost/gentaura}"
PKG="gentaura-base/chromium-ash"

# --- Cote SERVEUR BINHOST : emporter puis publier ---------------------------
build_and_publish() {
emerge -av --getbinpkg "${PKG}"           # deps binaires si dispo
emerge -av "${PKG}"                        # compilation lourde (32Go+)
quickpkg "${PKG}"                          # -> /var/cache/binpkg-packages
mkdir -p "${BINHOST_DIR}/All"
mv -f /var/cache/binpkg-packages/generic-packages/*.gpkg.tar \
"${BINHOST_DIR}/All/" || true
echo "Publie dans rsync://binhost.internal/${BINHOST_DIR##*/}/All/"
}

# --- Cote MACHINE CIBLE GentAura : acquisition chirurgicale ------------------
install_from_binhost() {
cat > /etc/portage/repos.conf/gentaura-binhost.conf <<CONF
[gentaura-binhost]
location = ${BINHOST_DIR}
priority = 50
CONF
echo "PORTAGE_BINHOST=${BINHOST_DIR}/All" >> /etc/portage/make.conf
emerge -gK --nodeps "${PKG}"   # telecharge et installe le binaire (~quelques sec.)
}

case "${1:-}" in
publish) build_and_publish ;;
install) install_from_binhost ;;
*) echo "usage: $0 publish|install"; exit 1 ;;
esac
