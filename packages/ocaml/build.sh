TERMUX_PKG_HOMEPAGE=https://ocaml.org
TERMUX_PKG_DESCRIPTION="Programming language supporting functional, imperative and object-oriented styles"
TERMUX_PKG_LICENSE="custom"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="5.5.1"
TERMUX_PKG_SRCURL="https://github.com/ocaml/ocaml/releases/download/${TERMUX_PKG_VERSION}/ocaml-${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=ae47728d0a876665ccc7b745e3a8d8c9ca5ba63c4f7a11d4db6cdbd1dbeef4bb
TERMUX_PKG_DEPENDS="pcre, openssl, libuuid, libandroid-shmem, zstd"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_HOSTBUILD=true
TERMUX_PKG_EXCLUDED_ARCHES="arm, i686"
TERMUX_PKG_UNDEF_SYMBOLS_FILES="./lib/ocaml/unix/unix.cmxs"

termux_step_host_build() {
	cp -a "$TERMUX_PKG_SRCDIR/." ./
	./configure --prefix="$TERMUX_PKG_HOSTBUILD_DIR/prefix" --disable-stdlib-manpages
	make -j "$TERMUX_PKG_MAKE_PROCESSES"
	make install
}

termux_step_pre_configure() {
	export PATH="$TERMUX_PKG_HOSTBUILD_DIR/prefix/bin:$PATH"
	export AS="$CC -c"
}

termux_step_configure() {
	./configure \
		--prefix="$TERMUX_PREFIX" \
		--mandir="$TERMUX_PREFIX/share/man" \
		--target="$TERMUX_HOST_PLATFORM" \
		--disable-stdlib-manpages
}

termux_step_make() {
	make -j "$TERMUX_PKG_MAKE_PROCESSES" crossopt
}

termux_step_make_install() {
	make installcross
}
