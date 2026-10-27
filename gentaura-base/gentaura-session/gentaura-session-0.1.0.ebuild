# Copyright 2026 GentAura Architecture Team
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit systemd

DESCRIPTION="GentAura session plumbing: systemd units, PAM/greetd wiring and environment scripts"
HOMEPAGE="https://github.com/gentaura/gentaura-os"
SRC_URI="https://github.com/gentaura/gentaura-os/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+greetd"

RDEPEND="
	sys-apps/systemd
	greetd? ( app-console/greetd )
	!greetd? ( sys-apps/systemd[sysv-utils] )
	gentaura-base/chromium-ash
"

src_install() {
	# --- Unites UTILISATEUR (session Ash/Exo pilotee par logind) ---
	insinto /usr/lib/systemd/user
	doins gentaura-base/gentaura-session/gentaura-shell.service
	doins gentaura-base/gentaura-session/gentaura-shell.target
	doins gentaura-base/gentaura-session/app-gentaura.slice

	# --- Script d'environnement Wayland pur (Jalon 1 : zero X11) ---
	dobin gentaura-base/gentaura-session/gentaura-session-start

	if use greetd; then
		insinto /etc/greetd
		newins gentaura-base/gentaura-session/greeter.conf greeter.conf.gentaura
	fi
}

pkg_postinst() {
	einfo "Activer la session GentAura :"
	einfo "  loginctl enable-linger \$USER"
	einfo "  systemctl --user enable --now gentaura-shell.target"
}
