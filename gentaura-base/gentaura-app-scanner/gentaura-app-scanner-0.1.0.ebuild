# Copyright 2026 GentAura Architecture Team
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cargo systemd

DESCRIPTION="Freedesktop .desktop indexer injecting Gentoo apps into the Ash Shelf/App List"
HOMEPAGE="https://github.com/gentaura/gentaura-os"
SRC_URI="https://github.com/gentaura/gentaura-os/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="sys-apps/systemd"

src_install() {
cargo_src_install
systemd_userunit_dounit "${S}/gentaura-base/gentaura-app-scanner/gentaura-app-scanner.service"
insinto /usr/share/gentaura
doins "${S}/gentaura-base/gentaura-app-scanner/app-gentaura.slice"
}
