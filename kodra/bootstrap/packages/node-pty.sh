# node-pty — the PTY layer behind the integrated terminal.
#
# remote/package.json pins ^1.2.0-beta.18, so that exact release is compiled
# here. Every prebuild npm would otherwise pick is glibc or musl and cannot load
# on bionic, which is why nothing is downloaded precompiled.
#
# The addon is built against the Node tree that was just installed into the
# prefix (--nodedir), not against a downloaded header tarball: the ABI number and
# the V8 headers have to be the ones the shipped node actually exports.
PKG_VERSION=1.2.0-beta.18
PKG_URL="https://registry.npmjs.org/node-pty/-/node-pty-$PKG_VERSION.tgz"
# dist.integrity from the npm registry packument for this exact version.
PKG_SHA512="3Rej3788OnasAwoSmTZhlCeUraJ9CQldtL5b571b9+3Nv47+PaxA5VPIGOOs+16OYQePTrC1Lrs8a9/df5WPRg=="

# What this package must leave in the prefix; build.sh fails the build if any of it
# is missing, so a wrong DESTDIR cannot pass as success.
PKG_ARTIFACTS="lib/node_modules/node-pty/build/Release/pty.node"

build() {
	local archive src nodedir shim dest
	archive="$(pkg_fetch_sha512 "$PKG_URL" "$PKG_SHA512")" || return 1
	pkg_extract "$archive" "$PKG_DIR" >/dev/null || return 1
	src="$PKG_DIR/package"
	nodedir="$BUILD_ROOT/src/node-$NODE_VERSION"

	if [ ! -f "$nodedir/common.gypi" ]; then
		ci_error "node-pty" "Node source tree missing at $nodedir (build node first)"
		return 1
	fi

	# bionic carries the posix_openpt family but forkpty(3)/openpty(3) are glibc
	# libutil inventions. Probe rather than assume, and force-include the shim only
	# when the platform really lacks them.
	shim=""
	if printf '#include <pty.h>\nint main(void){return forkpty(0,0,0,0);}\n' |
		"$CC" $ANDROID_CFLAGS -x c - -o /dev/null $ANDROID_LDFLAGS 2>/dev/null; then
		ci_notice "node-pty" "bionic provides forkpty(3); building without the shim"
	else
		ci_notice "node-pty" "bionic lacks forkpty(3); force-including the Kodra PTY shim"
		shim="-include $here/patches/node-pty-android.h"
	fi

	cd "$src" || return 1
	# --ignore-scripts: node-pty's install hook downloads prebuilds, which is exactly
	# what must not happen here.
	npm install --ignore-scripts --no-audit --no-fund >npm-install.log 2>&1 || {
		cat npm-install.log
		return 1
	}
	# Pin the build tool instead of relying on whatever node-gyp npm happens to bundle.
	npm install --no-save --ignore-scripts --no-audit --no-fund node-gyp@10 >npm-gyp.log 2>&1 || {
		cat npm-gyp.log
		return 1
	}

	CC="$CC" CXX="$CXX" AR="$AR" \
		CFLAGS="$ANDROID_CFLAGS -O2 $shim" \
		CXXFLAGS="$ANDROID_CFLAGS -O2 -fno-rtti -fno-exceptions $shim" \
		LDFLAGS="$ANDROID_LDFLAGS -L$KODRA_PREFIX/lib" \
		./node_modules/.bin/node-gyp rebuild \
		--nodedir="$nodedir" \
		--arch=arm64 \
		--release >node-gyp.log 2>&1 || {
		cat node-gyp.log
		return 1
	}

	# Runtime layout only: no prebuilds for other platforms, no build byproducts.
	dest="$KODRA_ROOTFS$KODRA_PREFIX/lib/node_modules/node-pty"
	mkdir -p "$dest/build/Release"
	cp -a lib package.json "$dest/"
	cp build/Release/pty.node "$dest/build/Release/pty.node" || return 1
	ci_notice "node-pty" "installed $(file -b "$dest/build/Release/pty.node")"
}
