# zlib — compression library git needs for packfiles and loose objects.
#
# Static only: linking it into git keeps the prefix free of a shared-object
# dependency for a library whose ABI nobody else in the prefix re-exports.
PKG_VERSION=1.3.1
PKG_URL="https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz"
# zlib publishes no checksum file; this is the digest the first build observed over
# TLS, recorded by `build.sh pin`, and enforced from then on.
PKG_SHA256=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23

# What this package must leave in the prefix; build.sh fails the build if any of it
# is missing, so a wrong DESTDIR cannot pass as success.
PKG_ARTIFACTS="lib/libz.a include/zlib.h"

build() {
	local archive
	archive="$(pkg_fetch "$PKG_URL" "$PKG_SHA256")" || return 1
	pkg_extract "$archive" "$PKG_DIR" >/dev/null || return 1
	cd "$PKG_DIR/zlib-$PKG_VERSION" || return 1

	# zlib's configure does not understand --host, so the target is asserted by
	# CC itself (the wrapper carries the Android triple) and CHOST only labels it.
	CHOST="$TARGET_TRIPLE" \
		CC="$CC" \
		CFLAGS="$ANDROID_CFLAGS -O2 -fPIC" \
		LDFLAGS="$ANDROID_LDFLAGS" \
		./configure --prefix="$KODRA_PREFIX" --static || return 1
	make -j"$(nproc)" || return 1
	make install DESTDIR="$KODRA_ROOTFS" || return 1
}
