# Copyright 2026 GentAura Architecture Team
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit meson pkgconfig

DESCRIPTION="Wayland/X11 compositor proxy for crosvm guests: projects VM windows into host Exo (zero-copy)"
HOMEPAGE="https://github.com/gentaura/gentaura-os"
SRC_URI="https://chromium.googlesource.com/chromiumos/platform2/+archive/${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/sommelier"

LICENSE="BSD-GentAura"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+virtio-gpu +xwl test"

RDEPEND="
dev-libs/wayland
media-libs/mesa[egl,gles2,gbm]
x11-libs/libxcb
virtio-gpu? ( sys-apps/virglrenderer )
xwl? ( x11-libs/xwl )
"
DEPEND="${RDEPEND}"
BDEPEND="dev-build/meson"

src_prepare() {
default
eapply "${FILESDIR}/01-gentaura-wayland-channel.patch" || die
}

src_configure() {
local emesonargs=(
-Dxwl=$(usex xwl true false)
-Dvirtio_gpu=$(usex virtio-gpu true false)
)
meson_src_configure
}
