#!/usr/bin/env bash
# Kodra cross toolchain: host clang + lld targeting aarch64-linux-android<API>.
#
# Why not the NDK's own clang
# ---------------------------
# Google publishes NDK host toolchains for linux-x86_64, darwin-x86_64 and
# darwin-arm64 only. On an aarch64 runner those binaries cannot execute, so the
# NDK cannot be used as a compiler there. What the NDK *is* authoritative for is
# the target: sysroot headers, API-level libc/libm/libdl, crt objects and the
# linker scripts are plain data and are host independent. Kodra therefore drives
# the runner's own clang at the Android triple and points it at that sysroot.
#
# This also keeps host tools native. V8 needs a host `mksnapshot` and `torque`
# built for the *host* while the target objects are Android; with an arm64 host
# and an arm64 Android target both are arm64 and both run natively.
#
# Usage:
#   toolchain.sh env > toolchain.env      # write the environment other scripts source
#   source toolchain.env                  # CC, CXX, AR, RANLIB, STRIP, LDFLAGS...
#   toolchain.sh verify                   # compile+link a probe, assert Android ELF
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ci.sh
. "$here/lib/ci.sh"

ANDROID_API="${ANDROID_API:-28}"
TARGET_TRIPLE="aarch64-linux-android"
TARGET="${TARGET_TRIPLE}${ANDROID_API}"
# The on-device prefix is fixed by the product decision (kodra/prefix-layout.json),
# so it is baked into rpath/staging rather than being configurable per build.
KODRA_PREFIX="${KODRA_PREFIX:-/data/data/dev.sonixdevs.kodra/files/usr}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/build-out}"
TOOLCHAIN_DIR="$BUILD_ROOT/toolchain"
NDK_SYSROOT="${ANDROID_NDK_ROOT:?ANDROID_NDK_ROOT must point at an installed NDK}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

# The NDK directory above is named linux-x86_64 even on other hosts; only the
# `sysroot/` beneath it is used, and that part is host independent.
# The NDK ships compiler-rt (never libgcc), and it lives in the NDK's own clang
# resource tree rather than in the sysroot. Host clang defaults to the gcc runtime
# for this triple and then fails with "unable to find library -lgcc", so the build
# names the runtime explicitly and adds the directory that holds it.
ndk_builtins_dir() {
	local candidate
	for candidate in "$ANDROID_NDK_ROOT"/toolchains/llvm/prebuilt/*/lib/clang/*/lib/linux; do
		[ -d "$candidate" ] && printf '%s' "$candidate" && return 0
	done
	return 1
}

# clang looks for its runtime and builtin headers relative to its *own* resource
# directory, so adding the NDK builtins to -L is not enough: the driver still
# names /usr/lib/llvm-<n>/lib/clang/<n>/lib/linux/libclang_rt.builtins-aarch64-
# android.a. Pointing --resource-dir at the NDK's clang tree makes the runtime,
# the builtin headers and the driver agree, and keeps the host's libstdc++ out of
# an Android link.
ndk_resource_dir() {
	local builtins
	builtins="$(ndk_builtins_dir)" || return 1
	(cd "$builtins/../.." && pwd -P)
}

ndk_api_libdir() {
	local candidate
	for candidate in "$NDK_SYSROOT/usr/lib/$TARGET_TRIPLE/$ANDROID_API" "$NDK_SYSROOT/usr/lib/$TARGET_TRIPLE"; do
		[ -d "$candidate" ] && printf '%s' "$candidate" && return 0
	done
	return 1
}

find_clang() {
	local candidate
	for candidate in clang clang-21 clang-20 clang-19 clang-18 clang-17; do
		if command -v "$candidate" >/dev/null 2>&1; then
			command -v "$candidate"
			return 0
		fi
	done
	return 1
}

find_cxx() {
	local candidate
	for candidate in clang++ clang++-21 clang++-20 clang++-19 clang++-18 clang++-17; do
		if command -v "$candidate" >/dev/null 2>&1; then
			command -v "$candidate"
			return 0
		fi
	done
	return 1
}

find_tool() {
	# llvm-ar-18 / llvm-ar / aarch64-linux-gnu-ar all work; the first that exists wins.
	local base="$1" candidate
	shift
	for candidate in "$base" "$@"; do
		if command -v "$candidate" >/dev/null 2>&1; then
			command -v "$candidate"
			return 0
		fi
	done
	return 1
}

write_env() {
	local clang ar ranlib strip ld_lld libdir builtins resdir
	clang="$(find_clang)" || {
		ci_error "toolchain" "no clang on PATH; install clang via apt"
		return 1
	}
	ar="$(find_tool llvm-ar llvm-ar-18 llvm-ar-19)" || return 1
	ranlib="$(find_tool llvm-ranlib llvm-ranlib-18 llvm-ranlib-19)" || return 1
	strip="$(find_tool llvm-strip llvm-strip-18 llvm-strip-19)" || return 1
	ld_lld="$(find_tool ld.lld ld.lld-18 ld.lld-19)" || return 1
	libdir="$(ndk_api_libdir)" || {
		ci_error "toolchain" "NDK sysroot has no aarch64-linux-android libs under $NDK_SYSROOT"
		return 1
	}
	builtins="$(ndk_builtins_dir)" || {
		ci_error "toolchain" "NDK has no compiler-rt builtins tree under $ANDROID_NDK_ROOT/toolchains/llvm/prebuilt"
		return 1
	}
	resdir="$(ndk_resource_dir)" || return 1

	local cxx
	cxx="$(find_cxx)" || {
		ci_error "toolchain" "no clang++ on PATH; install the clang C++ frontend via apt"
		return 1
	}

	mkdir -p "$TOOLCHAIN_DIR/bin"
	# autotools/cmake discover the compiler by name, so the wrappers carry the
	# Android triple in the file name: `--host=aarch64-linux-android` makes
	# configure look for aarch64-linux-android-clang, and the API-suffixed name is
	# what the NDK itself uses, so either spelling works.
	local wrapper
	for wrapper in "${TARGET}-clang" "${TARGET_TRIPLE}-clang"; do
		printf '#!/bin/sh\nexec %s --target=%s --sysroot=%s "$@"\n' "$clang" "$TARGET" "$NDK_SYSROOT" >"$TOOLCHAIN_DIR/bin/$wrapper"
		chmod +x "$TOOLCHAIN_DIR/bin/$wrapper"
	done
	for wrapper in "${TARGET}-clang++" "${TARGET_TRIPLE}-clang++"; do
		printf '#!/bin/sh\nexec %s --target=%s --sysroot=%s "$@"\n' "$cxx" "$TARGET" "$NDK_SYSROOT" >"$TOOLCHAIN_DIR/bin/$wrapper"
		chmod +x "$TOOLCHAIN_DIR/bin/$wrapper"
	done

	# Unquoted heredoc, so only variables this script has set may appear in it: an
	# unset name aborts under `set -u`, and a `$` inside a comment is expanded like
	# any other. The file is consumed line by line through $GITHUB_ENV, which does not
	# evaluate quoting — hence single-quoted values and no PATH entry.
	cat >"$TOOLCHAIN_DIR/toolchain.env" <<EOF
# Generated by kodra/bootstrap/toolchain.sh — do not edit.
export KODRA_PREFIX='$KODRA_PREFIX'
export ANDROID_API='$ANDROID_API'
export TARGET_TRIPLE='$TARGET_TRIPLE'
export TARGET='$TARGET'
export NDK_SYSROOT='$NDK_SYSROOT'
export CC='$TOOLCHAIN_DIR/bin/$TARGET-clang'
export CXX='$TOOLCHAIN_DIR/bin/$TARGET-clang++'
export AR='$ar'
export RANLIB='$ranlib'
export STRIP='$strip'
export LD='$ld_lld'
export KODRA_TOOLCHAIN_BIN='$TOOLCHAIN_DIR/bin'
# Bionic's dynamic linker path is fixed on Android; without it the binary would
# inherit the host's ld-linux and never start on a device. rpath points at the
# device prefix, so its lib directory resolves with no LD_LIBRARY_PATH, exactly as
# Android app binaries do.
# No -L entries on purpose. The NDK's unversioned aarch64-linux-android directory
# ships libc.a next to (for some releases, instead of) the shared stub, so adding it
# to the search path makes -lc resolve to the static libc: the executable then
# contains a private libc that bionic's linker never initialises, and the first libc
# call faults at 0x0. clang's driver already searches the sysroot and the API
# directory, and -resource-dir locates compiler-rt; nothing else is needed.
export ANDROID_LDFLAGS='--rtlib=compiler-rt -resource-dir=$resdir -fuse-ld=lld -Wl,--dynamic-linker=/system/bin/linker64 -Wl,-z,max-page-size=16384 -Wl,-rpath,$KODRA_PREFIX/lib'
# No -isystem for clang's own include directory. -resource-dir already points clang at
# it, and clang inserts it itself, after the C++ headers; spelling it out as -isystem
# puts it *first*, so <cstddef>'s include of <stddef.h> finds clang's stddef.h instead
# of libc++'s wrapper ("<cstddef> tried including <stddef.h> but didn't find libc++'s
# <stddef.h>"). C sources never noticed; the first C++ compile did.
export ANDROID_CFLAGS='-fPIC -D__ANDROID_API__=$ANDROID_API -DANDROID -resource-dir=$resdir -I$KODRA_PREFIX/include'
export ANDROID_CPPFLAGS='-I$KODRA_PREFIX/include'
export PKG_CONFIG_PATH='$KODRA_PREFIX/lib/pkgconfig'
export PKG_CONFIG_LIBDIR='$KODRA_PREFIX/lib/pkgconfig'
# Staging tree mirrors the device filesystem; a recipe that installs into the
# device prefix with this as DESTDIR therefore lands at its real on-device path.
export KODRA_ROOTFS='$BUILD_ROOT/rootfs'
EOF
	mkdir -p "$TOOLCHAIN_DIR/libdir"
	ln -sfn "$libdir" "$TOOLCHAIN_DIR/libdir"
	printf '%s\n' "$TOOLCHAIN_DIR/toolchain.env"
}

verify() {
	# shellcheck disable=SC1090
	. "$TOOLCHAIN_DIR/toolchain.env"
	local work="$BUILD_ROOT/toolchain-verify"
	local out="$work/hello"
	mkdir -p "$work"
	cp "$here/probe/hello.c" "$work/hello.c"
	"$CC" $ANDROID_CFLAGS "$work/hello.c" -o "$out" $ANDROID_LDFLAGS
	local interp
	interp="$(readelf -l "$out" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')"
	if [ "$interp" != "/system/bin/linker64" ]; then
		ci_error "toolchain" "probe interpreter is '$interp', expected /system/bin/linker64"
		return 1
	fi
	if readelf -V "$out" 2>/dev/null | grep -q 'GLIBC_'; then
		ci_error "toolchain" "probe requires glibc symbol versions; the sysroot was not used"
		return 1
	fi
	# A dynamically linked Android executable must import libc, not contain it. If the
	# link picked up the sysroot's libc.a, the binary carries a private copy whose
	# globals bionic's linker never initialises: it starts, then faults at 0x0 on the
	# first libc call. Checking for the definitions is what makes that visible, because
	# the interpreter and the ABI note look perfect either way.
	if ! readelf -dW "$out" | grep -q 'NEEDED.*libc\.so'; then
		ci_error "toolchain" "probe does not import libc.so; -lc resolved to the static libc"
		return 1
	fi
	local static_libc
	static_libc="$(nm --defined-only "$out" 2>/dev/null | awk '$3 == "getauxval" || $3 == "__libc_init" { print $3 }' | tr '\n' ' ')"
	if [ -n "$static_libc" ]; then
		ci_error "toolchain" "probe defines $static_libc itself: libc was linked statically"
		return 1
	fi
	local note
	note="$(readelf -n "$out" | grep -i 'android' || true)"
	if [ -z "$note" ]; then
		ci_error "toolchain" "probe has no Android ABI note; target triple was not applied"
		return 1
	fi
	ci_notice "toolchain" "clang $(command -v clang) -> $TARGET, interpreter $interp, ${note//$'\n'/ }"
}

case "${1:-}" in
env) write_env ;;
verify) verify ;;
*)
	echo "usage: $0 {env|verify}" >&2
	exit 2
	;;
esac
