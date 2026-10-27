# Copyright 2026 GentAura Architecture Team
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CHROMIUM_LANGS="en-US fr"
PYTHON_COMPAT=( python3_{11..13} )

inherit chromium-2 desktop flag-o-matic ninja-utils pax-check toolchain-funcs xdg-utils

DESCRIPTION="Ash/Aura/Exo window manager extracted from Chromium, running bare-metal on Gentoo via Ozone-DRM"
HOMEPAGE="https://github.com/gentaura/gentaura-os"
SRC_URI="https://redirector.gvt1.com/edgedl/chrome-linux/chrome-${PV}-source.tar.xz
	files/args.gn
	files/01-exo-xdg-runtime-socket.patch
	files/02-local-unix-session-bypass.patch
	files/03-shelf-freedesktop-launcher.patch"

LICENSE="BSD-GentAura"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+ozone-drm +vaapi +vulkan +pulseaudio headless test"
RESTRICT="!test? ( test )"

# ============================================================================
# STRESS-TEST ARCHITECTURAL - Ressources de compilation (cf. Point de vigilance)
# L'edition des liens (lld) de la cible ChromeOS exige >= 32 Go de RAM
# (ou 16 Go + 32 Go de swap ZRAM/NVMe) et ~80 Go dans /var/tmp/portage.
# Sur une machine cible GentAura legere : ne PAS compiler ici -> tirer le
# binaire du BINHOST (emerge --usepkg gentaura-base/chromium-ash).
# ============================================================================
RDEPEND="
	dev-libs/glib:2
	dev-libs/libevent
	dev-libs/nss
	media-libs/mesa[gbm(+),egl,gles2,vulkan?]
	x11-libs/libdrm
	media-libs/minigbm
	media-video/pipewire:=
	pulseaudio? ( media-sound/pulse-daemon )
	vaapi? ( media-libs/libva:=[X(-)?] )
	sys-apps/dbus
	sys-apps/systemd
	dev-libs/libinput
	net-misc/networkmanager
"
DEPEND="${RDEPEND}
	>=sys-devel/clang-18
	>=sys-devel/lld-18
"
BDEPEND="
	dev-build/gn
	dev-build/ninja
	virtual/pkgconfig
"

PATCHES=(
	"${FILESDIR}/01-exo-xdg-runtime-socket.patch"
	"${FILESDIR}/02-local-unix-session-bypass.patch"
	"${FILESDIR}/03-shelf-freedesktop-launcher.patch"
)

src_prepare() {
	chromium_src_prepare
	default
	# Injection du contrat GN (TDD Partie 2, Section 3)
	cp "${FILESDIR}/args.gn" "${S}/out/Release/args.gn" || die
}

src_configure() {
	local mygnargs=(
		use_ozone=true
		is_chromeos_device=false
	)
	use ozone-drm && mygnargs+=( ozone_platform="drm" )
	use vaapi     && mygnargs+=( use_vaapi=true )
	use vulkan    && mygnargs+=( enable_vulkan=true )
	use pulseaudio && mygnargs+=( use_pulseaudio=true )
	use headless  && mygnargs+=( ozone_platform_headless=true )

	# Jamais X11 sur l'hote GentAura (WON'T HAVE du PRD)
	mygnargs+=( ozone_platform_x11=false ozone_platform_wayland=false )

	# Toolchain systeme Gentoo (pas de sysroot downloadee)
	tc-export CC CXX AR RANLIB NM
	econf "${mygnargs[@]}"
}

src_compile() {
	# Cible Ash+Exo uniquement : on n'empaque pas tout le navigateur.
	eninja -C out/Release chrome ash_exo_shell || die "build monolithe"
}

src_install() {
	dobin out/Release/chrome
	newbin out/Release/ash_exo_shell gentaura-shell
	dodoc "${FILESDIR}/args.gn"
	doicon -s scalable files/gentaura-ash.svg || true
}

pkg_postinst() {
	elog "GentAura chromium-ash installe."
	elog "Compilation lourde validee uniquement sur BINHOST (32Go RAM / 80Go disque)."
	elog "Activer la session : systemctl --user enable --now gentaura-shell.target"
}
