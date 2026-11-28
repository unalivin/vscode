#!/usr/bin/env bash
# Kodra bootstrap build driver.
#
# This is Kodra's own package infrastructure: it replaces Termux's build system
# because the shipped artifacts must live in Kodra's prefix
# (/data/data/dev.sonixdevs.kodra/files/usr), not in com.termux's, and must be
# built against API 28 with our own toolchain. Termux's *prebuilt* packages are
# unusable here — their absolute paths and their signing identity are baked in —
# so everything is compiled from upstream source.
#
# Contract for a recipe (kodra/bootstrap/packages/<name>.sh):
#   PKG_VERSION  upstream version string
#   PKG_URL      source tarball
#   PKG_SHA256   sha256 of that tarball (a download without one is refused)
#   build()      runs inside $PKG_DIR with the toolchain environment exported
#
# The driver does the parts every package needs: verified download, extraction,
# install staging under the real device path, ELF auditing (every installed
# binary must be bionic-linked, never glibc), stripping, and per-package
# metadata under $PREFIX/etc/kodra/packages/<name>.json.
#
# Usage:
#   build.sh build <package>...       # build into $BUILD_ROOT/rootfs
#   build.sh verify                   # run smoke tests inside Android userland
#   build.sh pin <package>...         # report the sha256 of sources still marked PIN
#   build.sh list                     # known packages
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ci.sh
. "$here/lib/ci.sh"

BUILD_ROOT="${BUILD_ROOT:-$PWD/build-out}"
# Staging tree mirrors the device filesystem so `make install DESTDIR=$ROOTFS`
# with `--prefix=$KODRA_PREFIX` lands exactly where the app will find it.
ROOTFS="${KODRA_ROOTFS:-$BUILD_ROOT/rootfs}"
CACHE="$BUILD_ROOT/cache"
TOOLCHAIN_ENV="$BUILD_ROOT/toolchain/toolchain.env"

# shellcheck disable=SC1090
[ -f "$TOOLCHAIN_ENV" ] && . "$TOOLCHAIN_ENV"
KODRA_PREFIX="${KODRA_PREFIX:-/data/data/dev.sonixdevs.kodra/files/usr}"
PREFIX_DIR="$ROOTFS$KODRA_PREFIX"
: "${CC:?run toolchain.sh env first (CC is unset)}"

# Source, install and keep-out directories.
mkdir -p "$CACHE" "$PREFIX_DIR"/{bin,etc/kodra/packages,include,lib,libexec,share,tmp,var/log}

# log goes to stderr: recipes do `archive="$(pkg_fetch ...)"`, and anything printed on
# stdout would be captured into the variable instead of shown to the maintainer.
log() { printf '[kodra-bootstrap] %s\n' "$*" >&2; }

# The Node version is defined once, in packages/node.sh; node-pty builds its addon
# against that same tree, so the two can never drift apart. Read after log() exists:
# this runs at file scope, before any function that could define it has been called.
NODE_VERSION="$(. "$here/packages/node.sh" >/dev/null 2>&1; printf '%s' "$PKG_VERSION")"
export NODE_VERSION
log "node target: $NODE_VERSION"

# --- helpers available to recipes -------------------------------------------

log() { printf '[kodra-bootstrap] %s\n' "$*" >&2; }

# The Node version is defined once, in packages/node.sh; node-pty builds its addon
# against that same tree, so the two can never drift apart. Read after log() exists:
# this runs at file scope, before any function that could define it has been called.
NODE_VERSION="$(. "$here/packages/node.sh" >/dev/null 2>&1; printf '%s' "$PKG_VERSION")"
export NODE_VERSION
log "node target: $NODE_VERSION"

# --- helpers available to recipes -------------------------------------------

# A few upstream builds execute paths they are about to bake in. git runs
# $(SHELL_PATH) -c to decide whether the shell is modern enough, and SHELL_PATH has to
# stay the device path because it ends up in git's installed scripts.
#
# The staged bash cannot serve that purpose: it is an Android binary whose interpreter
# is /system/bin/linker64, so the host kernel answers ENOENT when make tries to run it.
# Instead, a host shim is written at the device path. It exists only on the build host,
# outside the prefix, and it executes the host's bash — the path git bakes in is the
# one that is correct on the device, where the real bash is installed.
prepare_device_paths() {
	local shim="$KODRA_PREFIX/bin/bash"
	[ -e "$shim" ] && return 0
	if ! sudo -n true 2>/dev/null; then
		ci_notice "device-path" "no passwordless sudo: $KODRA_PREFIX stays unreachable on this host"
		return 0
	fi
	sudo mkdir -p "$(dirname "$shim")"
	printf '#!/bin/sh\n# Build-host stand-in for the device shell; never shipped.\nexec /bin/bash "$@"\n' \
		| sudo tee "$shim" >/dev/null
	sudo chmod 0755 "$shim"
	ci_notice "device-path" "host shim at $shim runs the build host's bash"
}

log() { printf '[kodra-bootstrap] %s\n' "$*" >&2; }

# The Node version is defined once, in packages/node.sh; node-pty builds its addon
# against that same tree, so the two can never drift apart. Read after log() exists:
# this runs at file scope, before any function that could define it has been called.
NODE_VERSION="$(. "$here/packages/node.sh" >/dev/null 2>&1; printf '%s' "$PKG_VERSION")"
export NODE_VERSION
log "node target: $NODE_VERSION"

# --- helpers available to recipes -------------------------------------------

# A few upstream builds execute paths they are about to bake in. git, for one, runs
# $(SHELL_PATH) -c to decide whether the shell is modern enough and gives up with
# 'please_set_SHELL_PATH_to_a_more_modern_shell' when the device path does not exist
# on the build host. Pointing the real device path at the staged prefix keeps the
# correct path in the installed scripts and lets those checks pass.
prepare_device_paths() {
	local parent
	parent="$(dirname "$(dirname "$KODRA_PREFIX")")"
	[ -e "$parent/files/usr" ] && return 0
	if ! sudo -n true 2>/dev/null; then
		ci_notice "device-path" "no passwordless sudo: $KODRA_PREFIX stays unreachable on this host"
		return 0
	fi
	sudo mkdir -p "$parent/files"
	# A bind mount is nicer (no symlink for upstream tools to trip over) but workflow
	# containers usually refuse it. The fallback must be `ln -T`: given an existing
	# directory, plain `ln -s target dir` creates `dir/target` instead of replacing it,
	# and every path under it then points at a directory that is not the prefix.
	if ! { sudo mkdir -p "$parent/files/usr" && sudo mount --bind "$PREFIX_DIR" "$parent/files/usr"; } 2>/dev/null; then
		sudo rmdir "$parent/files/usr" 2>/dev/null || true
		sudo ln -sfnT "$PREFIX_DIR" "$parent/files/usr"
	fi
	if [ -e "$KODRA_PREFIX/etc/kodra/packages" ] || [ -x "$KODRA_PREFIX/bin/bash" ]; then
		ci_notice "device-path" "$KODRA_PREFIX resolves to $PREFIX_DIR"
	else
		ci_error "device-path" "$KODRA_PREFIX exists but does not resolve to $PREFIX_DIR"
	fi
}

pkg_fetch() {
	local url="$1" sha="$2"
	# A recipe may ship PKG_SHA256=PIN for a source whose upstream publishes no
	# checksum file. The first build then reports the digest it actually saw, over
	# TLS, and that value is committed; every later build enforces it. Guessing a
	# digest would defeat the check, and skipping it entirely would mean shipping
	# whatever the network handed us.
	local archive="$CACHE/$(basename "$url")"
	if [ ! -f "$archive" ]; then
		log "fetch $url"
		curl -fsSL --retry 3 --retry-delay 2 -o "$archive.part" "$url" || {
			ci_error "fetch" "download failed: $url"
			return 1
		}
		mv "$archive.part" "$archive"
	fi
	local actual
	actual="$(sha256sum "$archive" | cut -d' ' -f1)"
	if [ "$sha" = "PIN" ]; then
		ci_error "pin-required" "PKG_SHA256 for $(basename "$url") is PIN; commit this observed digest: $actual"
		return 1
	fi
	if [ "$actual" != "$sha" ]; then
		ci_error "fetch" "sha256 mismatch for $(basename "$url"): expected $sha, got $actual"
		return 1
	fi
	printf '%s' "$archive"
}

# pkg_fetch_sha512 <url> <base64 sha512> — for npm registry tarballs, whose signed
# `dist.integrity` is a sha512 rather than a sha256.
pkg_fetch_sha512() {
	local url="$1" expected="$2"
	local archive="$CACHE/$(basename "$url")"
	if [ ! -f "$archive" ]; then
		log "fetch $url"
		curl -fsSL --retry 3 --retry-delay 2 -o "$archive.part" "$url" || {
			ci_error "fetch" "download failed: $url"
			return 1
		}
		mv "$archive.part" "$archive"
	fi
	local actual
	actual="$(openssl dgst -sha512 -binary "$archive" | openssl base64 -A)"
	if [ "${actual#=}" = "${expected#=}" ] || [ "$actual" = "$expected" ]; then
		printf '%s' "$archive"
		return 0
	fi
	ci_error "fetch" "sha512 mismatch for $(basename "$url"): expected $expected, got $actual"
	return 1
}

# pkg_digest <url> — download and print the sha256 without enforcing anything.
# Used by `pin` to obtain the digest a recipe still marks as PIN; the digest is then
# committed and enforced by every later build.
pkg_digest() {
	local url="$1"
	local archive="$CACHE/$(basename "$url")"
	if [ ! -f "$archive" ]; then
		curl -fsSL --retry 3 --retry-delay 2 -o "$archive.part" "$url" || {
			ci_error "pin" "download failed: $url"
			return 1
		}
		mv "$archive.part" "$archive"
	fi
	sha256sum "$archive" | cut -d' ' -f1
}

# pkg_extract <archive> <dir> — extracts and prints the single top-level dir.
pkg_extract() {
	local archive="$1" dest="$2"
	mkdir -p "$dest"
	case "$archive" in
	*.tar.xz) tar -xJf "$archive" -C "$dest" ;;
	*.tar.gz | *.tgz) tar -xzf "$archive" -C "$dest" ;;
	*.tar.bz2) tar -xjf "$archive" -C "$dest" ;;
	*.zip) unzip -q "$archive" -d "$dest" ;;
	*)
		ci_error "extract" "unsupported archive type: $archive"
		return 1
		;;
	esac
}

# pkg_configure_env — the environment autotools/cmake recipes should inherit.
pkg_configure_env() {
	printf '%s' "$ANDROID_CFLAGS"
}

# --- ELF audit --------------------------------------------------------------

# Every ELF that reaches the prefix must be an Android ELF. A glibc-linked file
# here would install cleanly and then fail on the device with an unhelpful
# "cannot execute" message, so it is rejected at build time instead.
audit_elf() {
	local file="$1" kind interp bad=0
	kind="$(file -b "$file")"
	case "$kind" in
	*ELF*executable* | *ELF*shared\ object* | *ELF*pic*) ;;
	*) return 0 ;;
	esac
	# Archive members (.a) are not ELF files themselves; file(1) reports them as
	# current ar archive and the case above already skipped them.
	if readelf -V "$file" 2>/dev/null | grep -q 'GLIBC_[0-9]'; then
		ci_error "elf-audit" "$file requires glibc symbol versions"
		bad=1
	fi
	if readelf -d "$file" 2>/dev/null | grep -q 'ld-linux-aarch64'; then
		ci_error "elf-audit" "$file depends on the glibc dynamic loader"
		bad=1
	fi
	case "$kind" in
	*executable*)
		interp="$(readelf -l "$file" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')"
		if [ "$interp" != "/system/bin/linker64" ]; then
			ci_error "elf-audit" "$file interpreter is '${interp:-none}', expected /system/bin/linker64"
			bad=1
		fi
		;;
	esac
	if readelf -n "$file" 2>/dev/null | grep -qi 'android'; then
		: # Android ABI note present, as expected
	elif [ "$bad" -eq 0 ]; then
		# Shared objects built by the NDK sometimes carry the note only on the
		# executable; a missing note alone is not fatal, but record it.
		:
	fi
	return "$bad"
}

install_one() {
	local name="$1"
	local before after
	before="$(mktemp)"
	after="$(mktemp)"
	find "$PREFIX_DIR" -type f | sort >"$before"

	# shellcheck disable=SC1090
	. "$here/packages/$name.sh"
	PKG_NAME="$name"
	PKG_DIR="$BUILD_ROOT/src/$name-$PKG_VERSION"
	mkdir -p "$PKG_DIR"

	local log_file="$BUILD_ROOT/logs/$name.log"
	mkdir -p "$BUILD_ROOT/logs"
	build >"$log_file" 2>&1 || {
		# One annotation, not twenty: the runner stops publishing annotations after ten
		# per step, so a chatty failure hides its own cause. The last lines are the
		# cause, and the full log goes to the summary.
		# One annotation has room for thirty lines and GitHub keeps only the first ten
		# annotations, so both views go into this single message: what the build called an
		# error, and where it stopped.
		local errors
		# make's own 'Error 1' lines come last and would push the linker's message out of
		# the window, so they are filtered from the error list; the tail below still shows
		# where the build stopped.
		errors="$(grep -aE '(error:|error: |Error [0-9]|fatal error|undefined reference|cannot find|No such file)' "$log_file" \
			| grep -av 'make\[[0-9]*\]: \*\*\*' | grep -av '^make: \*\*\*' \
			| tail -n 5 | tr '\n' '~' | cut -c1-700)"
		ci_error "build:$name" "failed. errors: ${errors:-none matched} | tail: $(tail -n 4 "$log_file" | tr '\n' '~' | cut -c1-400)"
		# The single line above has a 700-character budget, which a recipe cannot always
		# squeeze a diagnosis into. The tail goes out as its own annotations as well, so
		# a few short lines are readable from an environment that cannot open job logs.
		ci_annotate_tail "build:$name tail" "$log_file" 4
		ci_summary "build:$name" "$log_file" 120
		return 1
	}

	find "$PREFIX_DIR" -type f | sort >"$after"
	local new_files
	new_files="$(comm -13 "$before" "$after")"

	# Strip and audit every new ELF, then record it.
	local f bad=0
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		case "$(file -b "$f")" in
		*ELF*executable* | *ELF*shared\ object*)
			audit_elf "$f" || bad=1
			"$STRIP" --strip-unneeded "$f" 2>/dev/null || true
			;;
		esac
	done <<EOF
$new_files
EOF
	[ "$bad" -eq 0 ] || return 1

	# Declared artifacts must exist in the staged prefix. Without this a package can
	# "build" successfully and land nowhere — a DESTDIR or prefix mistake then shows up
	# much later as an unexplainable missing file in the next package's build.
	local artifact missing=""
	for artifact in ${PKG_ARTIFACTS:-}; do
		[ -e "$PREFIX_DIR/$artifact" ] || missing="$missing $artifact"
	done
	if [ -n "$missing" ]; then
		ci_error "build:$name" "installed nothing at:$missing (prefix bin: $(ls "$PREFIX_DIR/bin" 2>/dev/null | tr '\n' ' '))"
		return 1
	fi

	local json="$PREFIX_DIR/etc/kodra/packages/$name.json"
	{
		printf '{\n  "name": "%s",\n  "version": "%s",\n  "source": "%s",\n  "sha256": "%s",\n  "files": [\n' \
			"$name" "$PKG_VERSION" "$PKG_URL" "$PKG_SHA256"
		printf '%s\n' "$new_files" | sed -e "s|^$PREFIX_DIR||" -e 's|.*|    "&",|' | sed '$ s/,$//'
		printf '  ]\n}\n'
	} >"$json"

	log "$name $PKG_VERSION: $(printf '%s\n' "$new_files" | grep -c . || true) files"
	rm -f "$before" "$after"
}

# --- smoke tests run inside the Android userland ----------------------------

verify() {
	local rt="$here/android-runtime.sh"
	local failed=0

	expect() {
		local title="$1" expected="$2"
		shift 2
		local out
		if ! out="$("$rt" run "$@" 2>&1)"; then
			ci_error "smoke:$title" "command failed: $* -> $out"
			failed=1
			return 0
		fi
		case "$out" in
		*"$expected"*) ci_notice "smoke:$title" "$out" ;;
		*)
			ci_error "smoke:$title" "output did not contain '$expected': $out"
			failed=1
			;;
		esac
		{
			printf '#### %s\n```text\n%s\n```\n' "$title" "$out"
		} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
	}

	expect bash-version "GNU bash" "$KODRA_PREFIX/bin/bash" --version
	expect bash-echo "kodra-bash-ok" "$KODRA_PREFIX/bin/bash" -c 'echo kodra-bash-ok; echo "HOME=$HOME PREFIX=$PREFIX"; pwd'
	expect git-version "git version" "$KODRA_PREFIX/bin/git" --version

	# A repository round-trip proves the binary works, not just that it reports a
	# version: init, write, add, commit with an identity, read it back.
	local repo_test='
	  set -e
	  export HOME=/tmp HOME_OVERRIDE=1
	  rm -rf /tmp/repo && mkdir -p /tmp/repo && cd /tmp/repo
	  git init -q .
	  git config user.email kodra@example.invalid
	  git config user.name Kodra
	  printf "hello\n" > a.txt
	  git add a.txt
	  git commit -qm "first"
	  git log --format=%s -1
	  git ls-files
	'
	expect git-roundtrip "first" "$KODRA_PREFIX/bin/bash" -c "$repo_test"

	expect node-version "v24.22.1" "$KODRA_PREFIX/bin/node" --version
	expect node-arch "arm64 bionic" "$KODRA_PREFIX/bin/node" -e '
	  const { versions, platform, arch } = process;
	  console.log(`${arch} ${platform} uv=${versions.uv} v8=${versions.v8}`);
	'

	# node-pty must allocate a real PTY, fork a real Android process, and round-trip
	# bytes through it. A stub or a mocked module cannot produce "PTY_OK" here.
	local pty_test='
	  const pty = require("node-pty");
	  const shell = process.env.PREFIX + "/bin/bash";
	  const term = pty.spawn(shell, ["-lc", "echo PTY_OK; echo TERM=$TERM"], {
	    name: "xterm-256color", cols: 80, rows: 24, cwd: "/tmp", env: process.env,
	  });
	  let buf = "";
	  const timer = setTimeout(() => { console.error("timeout: " + JSON.stringify(buf)); process.exit(1); }, 20000);
	  term.onData((d) => {
	    buf += d;
	    if (buf.includes("PTY_OK")) { clearTimeout(timer); term.kill(); console.log("PTY_OK pty=" + process.versions.uv); process.exit(0); }
	  });
	'
	expect node-pty "PTY_OK" "$KODRA_PREFIX/bin/node" -e "$pty_test"

	return "$failed"
}

case "${1:-}" in
build)
	shift
	[ "$#" -gt 0 ] || {
		echo "usage: $0 build <package>..." >&2
		exit 2
	}
	for name in "$@"; do
		log "=== $name ==="
		install_one "$name" || exit 1
	done
	;;
verify) verify ;;
pin)
	shift
	[ "$#" -gt 0 ] || {
		echo "usage: $0 pin <package>..." >&2
		exit 2
	}
	for name in "$@"; do
		# shellcheck disable=SC1090
		. "$here/packages/$name.sh"
		if [ "$PKG_SHA256" != "PIN" ]; then
			log "$name already pinned: $PKG_SHA256"
			continue
		fi
		digest="$(pkg_digest "$PKG_URL")" || exit 1
		log "$name $PKG_URL sha256=$digest"
		ci_notice "pin:$name" "PKG_SHA256=$digest"
	done
	;;
list)
	for f in "$here"/packages/*.sh; do basename "$f" .sh; done
	;;
*)
	echo "usage: $0 {build <package>...|pin <package>...|verify|list}" >&2
	exit 2
	;;
esac
