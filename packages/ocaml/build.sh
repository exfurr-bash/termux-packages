TERMUX_PKG_HOMEPAGE=https://ocaml.org
TERMUX_PKG_DESCRIPTION="Programming language supporting functional, imperative and object-oriented styles"
TERMUX_PKG_LICENSE="custom"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="5.5.1"
TERMUX_PKG_REVISION=1
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

termux_step_post_massage() {
	# On-device usability (report.txt F1): the plain compiler driver
	# names are installed as symlinks to the .opt binaries, which are
	# build-machine (x86_64) executables from the cross build and cannot
	# run on device. Point them at the .byte variants instead, which run
	# through the target ocamlrun. (ocamlopt.byte still emits native
	# code, given a C toolchain on device.) The .opt files stay in place
	# for use as build-machine tools when cross-compiling in Docker.
	for _f in ocamlc ocamlopt ocamldep ocamllex ocamlobjinfo; do
		ln -sf "$_f.byte" "bin/$_f"
	done
	# Bytecode executables linked with these stub libraries look them up
	# under the build-machine (x86_64-pc-linux-gnu) name instead of the
	# target one (report.txt F2), so alias each shipped stub library.
	# This is a no-op for lookups that already use the target name.
	local _f _alias
	for _f in lib/ocaml/stublibs/dll*.so; do
		[ -L "$_f" ] && continue
		if [[ $(basename "$_f") =~ ^(dll[^-]*)-(.+)(-a[0-9]+\.so)$ ]]; then
			_alias="${BASH_REMATCH[1]}-x86_64-pc-linux-gnu${BASH_REMATCH[3]}"
		else
			_alias="$(basename "$_f" .so)-x86_64-pc-linux-gnu.so"
		fi
		ln -sf "$(basename "$_f")" "lib/ocaml/stublibs/$_alias"
	done
}
