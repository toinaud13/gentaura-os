# Copyright 2026 GentAura Architecture Team
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	crosvm-132.0.0
	rutabaga_gfx-0.1.4
"
inherit cargo linux-info systemd

DESCRIPTION="crosvm VMM tuned for GentAura: Rutabaga zero-copy virtio-gpu cross-domain + PipeWire audio"
HOMEPAGE="https://github.com/gentaura/gentaura-os"
SRC_URI="https://github.com/google/crosvm/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz
	files/launch-crosvm-aura.sh"

LICENSE="BSD-GentAura"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+gpu +pipewire +balloon +virtio-gpu debug"
REQUIRED_USE="virtio-gpu? ( gpu )"

RDEPEND="
	sys-kernel/linux-firmware
	gpu? ( media-libs/mesa[gbm] )
	pipewire? ( media-video/pipewire )
	balloon? ( app-emulation/qemu-guest-agent )
"
DEPEND="${RDEPEND}
	dev-lang/rust
"

pkg_setup() {
	# Verrouillage du contrat noyau (TDD Partie 2, Section 2) cote hote :
	# sans ces options, le pipeline Zero-Copy est IMPOSSIBLE.
	kernel_is -ge 6 6 || die "GentAura crosvm requiert un noyau >= 6.6 (udmabuf/sync_file)"
	check_config_gentaura() {
		if ! linux_config_exists; then
			ewarn "Pas de .config noyau detecte : verifier manuellement CONFIG_UDMABUF/CONFIG_VHOST_VSOCK."
			return
		fi
		local opt
		for opt in CONFIG_UDMABUF CONFIG_VHOST_VSOCK CONFIG_KVM CONFIG_SYNC_FILE; do
		/linux-config-get-option "${opt}" >/dev/null \
				|| die "${opt} requis par le pipeline Zero-Copy GentAura (voir kernel/gentaura.config)"
		done
	}
	check_config_gentaura
}

src_configure() {
	# Selection des features cargo de crosvm (cf. Cargo.toml amont) :
	#   gpu         -> rutabaga_gfx + virtio-gpu (cross-domain / virgl2)
	#   audio       -> pont AudioUtil vers PipeWire (a11y-sound, pas CRAS hote)
	#   balloon     -> arbitrage RAM dynamique hote <-> VM (NFR Resilience)
	local myfeatures=( default )
	use gpu        && myfeatures+=( gpu )
	use pipewire   && myfeatures+=( audio )
	use balloon    && myfeatures+=( balloon )
	use debug      && myfeatures+=( slog_debug )
	cargo_src_configure "${myfeatures[@]}"
}

src_install() {
	cargo_src_install
	# Script de reference du pipeline Zero-Copy (TDD Section 5)
	newbin "${FILESDIR}/launch-crosvm-aura.sh" gentaura-run-vm
	# Regles udev : acces /dev/kvm et /dev/vhost-vsock au groupe kvm
	insinto /usr/lib/udev/rules.d
	doins "${FILESDIR}/60-gentaura-crosvm.rules"
}
