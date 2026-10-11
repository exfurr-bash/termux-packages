TERMUX_PKG_HOMEPAGE=https://opam.ocaml.org
TERMUX_PKG_DESCRIPTION="Source-based OCaml package manager"
TERMUX_PKG_LICENSE="LGPL-2.1-only"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="2.6.1"
TERMUX_PKG_SRCURL=https://github.com/ocaml/opam/releases/download/${TERMUX_PKG_VERSION}/opam-full-${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=ebbaffa4192e69d612d2c1a5fc5a15b32730322d7e34bc4456ad4076bb987007
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="git, libcurl, patch, unzip"
TERMUX_PKG_BUILD_DEPENDS="ocaml"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_EXCLUDED_ARCHES="arm, i686"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="--with-vendored-deps --disable-static --without-mccs"

termux_step_pre_configure() {
	# The `ocaml` package installs a build-machine-runnable cross
	# compiler into $TERMUX_PREFIX/bin, but that dir is not on PATH
	# during dependent builds, so `configure` cannot find `ocamlc`
	# (same pattern as packages/ocaml/build.sh termux_step_pre_configure).
	export PATH="$TERMUX_PREFIX/bin:$PATH"
	# Cross-compiling only: shadow the compiler drivers with names that
	# are guaranteed build-machine-runnable. Since the `ocaml` package
	# points the plain names (ocamlc, ocamlopt, ...) at the .byte
	# variants for on-device use (report.txt F1), and those need a
	# target-arch ocamlrun, resolve them here to the .opt binaries
	# (x86_64, runnable on the build machine) instead. Same for
	# ocamlyacc, which only exists for the target arch in the prefix.
	# On-device builds need none of this (build arch == target arch).
	if [ "$TERMUX_ON_DEVICE_BUILD" = true ]; then return; fi
	local _host_bin="$TERMUX_TOPDIR/ocaml/host-build/prefix/bin"
	if [ ! -x "$_host_bin/ocamlc" ]; then
		termux_error_exit "host ocamlc not found at $_host_bin (is 'ocaml' built from source?)"
	fi
	mkdir -p "$TERMUX_PKG_TMPDIR/ocaml-host-bin"
	ln -sf "$_host_bin/ocamlyacc" "$TERMUX_PKG_TMPDIR/ocaml-host-bin/ocamlyacc"
	# NOTE: keep an `ocaml` next to `ocamlc` here: dune evaluates
	# OCaml-syntax dune files by compiling them with `ocamlc` and running
	# the result with the `ocaml` found in the same directory.
	ln -sf "$_host_bin/ocaml" "$TERMUX_PKG_TMPDIR/ocaml-host-bin/ocaml"
	# Same-dir companions dune may ask for: the prefix ocamlmklib runs
	# here and is configured with the cross toolchain (verified: it
	# shells out to aarch64-linux-android-clang), unlike the host one
	# which would link with the build-machine ld.
	ln -sf "$TERMUX_PREFIX/bin/ocamlmklib" "$TERMUX_PKG_TMPDIR/ocaml-host-bin/ocamlmklib"
	local _t
	for _t in ocamlc ocamlopt ocamldep ocamllex ocamlobjinfo; do
		ln -sf "$TERMUX_PREFIX/bin/$_t.opt" "$TERMUX_PKG_TMPDIR/ocaml-host-bin/$_t"
	done
	export PATH="$TERMUX_PKG_TMPDIR/ocaml-host-bin:$PATH"
}

termux_step_post_configure() {
	# Cross-compiling only. The main (cross) dune build cannot *run*
	# anything it compiles (target = aarch64, build machine = x86_64),
	# but several vendored generators must run at build time. Strategy:
	# run a host-only dune pass that produces exactly those generated
	# files, copy them back into the source tree, and neutralize the
	# corresponding rules so the cross build skips them. The rule fixes
	# live as *.patch.cross files next to build.sh, applied explicitly
	# in step 4 (same idea as the build system's *.patch.beforehostbuild
	# convention): plain *.patch files are auto-applied before
	# configure, but the vendored trees only materialize during
	# configure (and native builds must keep generating). Three of them
	# (checkseum-stddef-static, dose3-git-version-ocaml,
	# stdlib-shims-static-dune) are additionally native-safe. On-device
	# builds skip everything below (build arch == target arch).
	if [ "$TERMUX_ON_DEVICE_BUILD" = true ]; then return; fi

	local _host_bin="$TERMUX_TOPDIR/ocaml/host-build/prefix/bin"
	local _src="$TERMUX_PKG_SRCDIR"
	local _host_dune="$_src/src_ext/dune-local/_boot/dune.exe"

	# 1. Build-machine tools were shadowed in termux_step_pre_configure
	#    (ocamlyacc plus the .opt compiler drivers, all runnable here);
	#    the PATH set up there is still in effect.

	# 2. Bootstrap a build-machine dune with the host OCaml, in place:
	#    the vendored bootstrap (`ocaml boot/bootstrap.ml`) links the
	#    *target* runtime, producing an aarch64 `.duneboot.exe` that
	#    cannot run here ("Exec format error"). The fresh _boot/dune.exe
	#    is newer than src_ext/dune-local.stamp, so make skips its own
	#    bootstrap rule and uses it directly.
	(
		cd "$_src/src_ext/dune-local"
		PATH="$_host_bin:$PATH" "$_host_bin/ocaml" boot/bootstrap.ml
		# Ensure make sees it as fresh:
		touch _boot/dune.exe
	)

	# 3. Host pass: generate opamBaseParser.{ml,mli} (needs a runnable
	#    menhir stage1+stage2) and menhirLib.{ml,mli} (needs pack.exe)
	#    with the host toolchain, plus a host cppo binary (extlib
	#    preprocesses its sources by *running* %{bin:cppo}).
	local _build="$_src/_build/default"
	(
		cd "$_src"
		PATH="$_host_bin:$TERMUX_PKG_TMPDIR/ocaml-host-bin:$PATH" \
			"$_host_dune" build \
			src_ext/opam-file-format/src/opamBaseParser.ml \
			src_ext/menhir/lib/pack/menhirLib.ml \
			src_ext/menhir/lib/pack/menhirLib.mli \
			src_ext/cppo/src/cppo_main.exe
	)
	# Snapshot the host cppo: the main build would rebuild it for the
	# target arch, so it must not stay in _build.
	cp "$_build/src_ext/cppo/src/cppo_main.exe" \
		"$TERMUX_PKG_TMPDIR/ocaml-host-bin/cppo"
	cp "$_build/src_ext/opam-file-format/src/opamBaseParser.ml" \
		"$_src/src_ext/opam-file-format/src/opamBaseParser.ml"
	if [ -e "$_build/src_ext/opam-file-format/src/opamBaseParser.mli" ]; then
		cp "$_build/src_ext/opam-file-format/src/opamBaseParser.mli" \
			"$_src/src_ext/opam-file-format/src/opamBaseParser.mli"
	fi
	cp "$_build/src_ext/menhir/lib/pack/menhirLib.ml" \
		"$_src/src_ext/menhir/lib/pack/menhirLib.ml"
	cp "$_build/src_ext/menhir/lib/pack/menhirLib.mli" \
		"$_src/src_ext/menhir/lib/pack/menhirLib.mli"

	# 4. Apply the cross-only rule neutralizations as patch files.
	#    They use the .patch.cross suffix (mirroring the build system's
	#    own *.patch.beforehostbuild convention) so the build system
	#    does not auto-apply them: auto-apply runs before configure,
	#    but the vendored trees only materialize during configure, and
	#    native builds must keep generating. Applied here they fail
	#    loudly on upstream drift via patch itself. The generated
	#    outputs they need were copied into the tree in step 3.
	cd "$_src"
	for _p in "$TERMUX_PKG_BUILDER_DIR"/*.patch.cross; do
		# NOTE: absolute path on purpose -- $TERMUX_PREFIX/bin/patch
		# targets Android and cannot run on the build machine.
		/usr/bin/patch -p1 -i "$_p"
	done
	# Sole remaining script edit: extlib must run cppo from the snapshot
	# taken above, whose absolute path only exists in this build dir and
	# therefore cannot be baked into a static patch (fail fast if
	# upstream rewords the stanza).
	_f="$_src/src_ext/extlib/src/dune"
	grep -q '%{bin:cppo}' "$_f" \
		|| termux_error_exit "extlib cppo stanza changed, update recipe"
	# Point at the host cppo snapshot by absolute path: dune resolves a
	# bare `cppo` name to the target-arch binary built in-tree, which
	# cannot run here. (Absolute paths are used literally and the action
	# sandbox is a plain directory, so this is safe.)
	sed -i "s#%{bin:cppo}#$TERMUX_PKG_TMPDIR/ocaml-host-bin/cppo#" "$_f"
}

termux_step_make_install() {
	# `make install` runs the just-built (target-arch) opam-installer,
	# which cannot execute here. Both .install files only place a single
	# binary, so install them directly (same layout opam-installer would
	# produce: $PREFIX/bin/<name>). NOTE (Android): bubblewrap
	# sandboxing is unsupported, so after install run:
	#   opam init --disable-sandboxing
	install -Dm755 "_build/install/default/bin/opam" \
		"$TERMUX_PREFIX/bin/opam"
	install -Dm755 "_build/install/default/bin/opam-installer" \
		"$TERMUX_PREFIX/bin/opam-installer"
}
