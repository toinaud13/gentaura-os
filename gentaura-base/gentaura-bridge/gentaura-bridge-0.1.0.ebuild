# Copyright 2026 GentAura Architecture Team
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
tokio-1.40.0
zbus-4.4.0
serde-1.0.210
tracing-0.1.40
tracing-subscriber-0.3.18
"
inherit cargo systemd

DESCRIPTION="D-Bus gateway daemon translating Ash ChromeOS calls to NetworkManager/UPower/PipeWire"
HOMEPAGE="https://github.com/gentaura/gentaura-os"
SRC_URI="https://github.com/gentaura/gentaura-os/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

DEPEND="sys-apps/dbus"
RDEPEND="${DEPEND}"

src_compile() {
cargo_src_compile
}

src_install() {
cargo_src_install
systemd_dounit "${S}/gentaura-base/gentaura-bridge/gentaura-bridge.service"
}
