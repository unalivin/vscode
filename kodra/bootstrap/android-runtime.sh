#!/usr/bin/env bash
# Provides a real Android/bionic userland and a way to execute Kodra binaries on it.
#
# The problem this solves
# -----------------------
# A GitHub runner is Linux with a glibc userland. A Kodra binary is Android: its ELF
# interpreter is /system/bin/linker64 and its libraries are bionic. Executing it
# directly on the runner fails with "No such file or directory" (the interpreter),
# and faking that with a shim would prove nothing.
#
# So this script installs the genuine article: /system/bin/linker64 and /system/lib64
# copied out of an official arm64 Android system image, inside a chroot at their real
# paths. Kodra's prefix is bind-mounted at its real device path inside that chroot, so
# binaries find their own rpath and behave exactly as they will on the device.
#
# CPU is the runner's own aarch64 core; nothing is emulated. The kernel is the
# runner's Linux kernel, which is the same syscall surface bionic targets. This is not
# a substitute for a device — SELinux, Play services and OEM kernels are absent — but
# it does execute the real linker, the real libc and the real binaries.
#
# Usage:
#   android-runtime.sh install            # fetch an image, build the chroot
#   android-runtime.sh run <cmd...>       # run a command inside the chroot
#   android-runtime.sh shell -c <script>  # run through /system/bin/sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ci.sh
. "$here/lib/ci.sh"

ANDROID_API="${ANDROID_API:-28}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/build-out}"
ROOT="${ANDROID_ROOT:-$BUILD_ROOT/android-root}"
ROOTFS="${KODRA_ROOTFS:-$BUILD_ROOT/rootfs}"
KODRA_PREFIX="${KODRA_PREFIX:-/data/data/dev.sonixdevs.kodra/files/usr}"
# The whole app-private files/ tree is mounted (not just usr/), because $HOME lives
# beside the prefix and git, npm and ssh all write into it.
FILES_DIR="$(dirname "$KODRA_PREFIX")"
KODRA_HOME="$FILES_DIR/home"
# Candidates are tried in order: arm64 images are not published for every API and
# flavour combination, and the first one that downloads is the one used.
IMAGE_CANDIDATES="${IMAGE_CANDIDATES:-system-images;android-${ANDROID_API};default;arm64-v8a system-images;android-${ANDROID_API};google_apis;arm64-v8a system-images;android-30;google_apis;arm64-v8a}"

mkdir -p "$BUILD_ROOT"

log() { printf '[kodra-runtime] %s\n' "$*"; }

# Android system images ship in libsparse format, which the kernel cannot loop-mount.
# The converter is a no-op on an already-raw image, so it is safe to call always.
desparse() {
	local path="$1" out
	out="$(python3 "$here/lib/sparse2raw.py" "$path")" || {
		ci_error "android-runtime" "could not convert $path from sparse to raw"
		return 1
	}
	[ -n "$out" ] && log "$out"
	return 0
}

# Google publishes every system image in a repository index together with its
# checksum. Reading that index directly avoids `sdkmanager`, which treats the emulator
# package as a hard dependency of each image (about a gigabyte that a chroot never
# runs) and fails when it cannot resolve it.
index_lookup() {
	local index_file="$1" wanted="$2"
	python3 - "$index_file" "$wanted" <<'PY'
import sys
import xml.etree.ElementTree as ET

index_file, wanted = sys.argv[1], sys.argv[2]
try:
    root = ET.parse(index_file).getroot()
except ET.ParseError as exc:
    sys.exit(f"unparseable index: {exc}")

for package in root.iter("remotePackage"):
    if package.get("path") != wanted:
        continue
    for archive in package.iter("archive"):
        host_os = (archive.findtext("host-os") or "any").strip()
        if host_os not in ("any", "linux"):
            continue
        url = archive.findtext("complete/url")
        checksum = archive.findtext("complete/checksum")
        if url and checksum:
            print(url, checksum)
            sys.exit(0)
sys.exit(1)
PY
}

fetch_image() {
	local pkg="$1" index_url url_sum url sum image_dir tmp actual found
	url=""
	# AOSP ("default") and Google APIs images live in separate index files.
	for index_url in \
		"https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml" \
		"https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-1.xml" \
		"https://dl.google.com/android/repository/sys-img/android/sys-img2-3.xml" \
		"https://dl.google.com/android/repository/sys-img/android/sys-img2-1.xml"; do
		curl -fsSL --retry 2 -o "$BUILD_ROOT/sys-img-index.xml" "$index_url" 2>/dev/null || continue
		if url_sum="$(index_lookup "$BUILD_ROOT/sys-img-index.xml" "$pkg")"; then
			url="${url_sum%% *}"
			sum="${url_sum##* }"
			# sys-img indexes publish archive names relative to the index itself.
			case "$url" in
			http*) : ;;
			*) url="$(dirname "$index_url")/$url" ;;
			esac
			break
		fi
	done
	[ -n "$url" ] || return 1

	# The package path maps onto sdkmanager's on-disk layout, so the rest of the
	# script does not care how the image arrived.
	image_dir="${ANDROID_HOME:-/usr/local/lib/android/sdk}/system-images/$(printf '%s' "$pkg" | cut -d';' -f2-4 | tr ';' '/')"
	tmp="$BUILD_ROOT/sys-img.zip"
	log "downloading $url"
	curl -fsSL --retry 3 -o "$tmp" "$url" || return 1
	actual="$(sha1sum "$tmp" | cut -d' ' -f1)"
	[ "$actual" = "$sum" ] || {
		ci_error "android-runtime" "system image checksum mismatch: expected $sum, got $actual"
		return 1
	}
	mkdir -p "$(dirname "$image_dir")"
	unzip -q -o "$tmp" -d "$(dirname "$image_dir")" || return 1
	if [ ! -f "$image_dir/system.img" ]; then
		# Some archives unpack as <flavour>/<abi>/; find the image instead of guessing.
		found="$(find "$(dirname "$image_dir")" -maxdepth 3 -name system.img -print -quit)"
		[ -n "$found" ] || {
			ci_error "android-runtime" "no system.img inside $tmp"
			return 1
		}
		image_dir="$(dirname "$found")"
	fi
	IMAGE_DIR="$image_dir"
	ci_notice "android-runtime" "system image: $pkg -> $image_dir"
}

# Google's images are ext4, but not always at offset 0: some are raw disk images
# carrying an MBR or GPT first. Rather than mounting blind and reporting "bad
# superblock", find the filesystem and mount at its offset.
fs_offset() {
	python3 - "$1" <<'PY'
import struct
import sys

path = sys.argv[1]
EXT_MAGIC = b"\x53\xef"  # 0xEF53 little-endian, at 0x438 into the filesystem


def is_ext(f, offset):
    f.seek(offset + 0x438)
    return f.read(2) == EXT_MAGIC


with open(path, "rb") as f:
    if is_ext(f, 0):
        print(0)
        raise SystemExit(0)

    # MBR: four 16-byte entries at 0x1BE, start LBA at +8.
    f.seek(0x1BE)
    entries = f.read(64)
    for i in range(4):
        entry = entries[i * 16 : (i + 1) * 16]
        if len(entry) < 16:
            break
        lba = struct.unpack("<I", entry[8:12])[0]
        if lba and is_ext(f, lba * 512):
            print(lba * 512)
            raise SystemExit(0)

    # GPT: header at LBA 1, first usable partition entry at LBA 2.
    f.seek(512)
    if f.read(8) == b"EFI PART":
        f.seek(2 * 512)
        entry = f.read(128)
        first_lba = struct.unpack("<Q", entry[32:40])[0]
        if first_lba and is_ext(f, first_lba * 512):
            print(first_lba * 512)
            raise SystemExit(0)
raise SystemExit(1)
PY
}

# mount_image <image> <offset> <target>
mount_image() {
	local img="$1" offset="$2" target="$3" opts="loop,ro"
	[ "$offset" != "0" ] && opts="$opts,offset=$offset"
	sudo mount -o "$opts" "$img" "$target"
}

install() {
	local image found=""
	for image in $IMAGE_CANDIDATES; do
		if fetch_image "$image"; then
			found="$image"
			break
		fi
	done
	[ -n "$found" ] || {
		ci_error "android-runtime" "no arm64 system image could be downloaded; tried: $IMAGE_CANDIDATES"
		return 1
	}

	local img="$IMAGE_DIR/system.img" offset
	desparse "$img"
	ci_notice "android-runtime" "system.img: $(file -b "$img"), $(stat -c %s "$img") bytes"

	# The chroot is a directory tree whose /system is the image itself.
	sudo mkdir -p "$ROOT/system" "$ROOT/proc" "$ROOT/dev/pts" "$ROOT/tmp"
	offset="$(fs_offset "$img")" || {
		ci_error "android-runtime" "no ext4 superblock found in $img (first bytes: $(od -An -tx1 -N16 "$img"))"
		return 1
	}
	# The image is a disk, not necessarily the system partition itself. Mount it aside
	# and then bind the directory that actually holds /bin/linker64 into place, so the
	# chroot sees the device's real /system layout either way.
	sudo mkdir -p "$ROOT/disk"
	if ! mount_image "$img" "$offset" "$ROOT/disk"; then
		ci_error "android-runtime" "could not loop-mount $img at offset $offset ($(file -b "$img"))"
		return 1
	fi

	local system_src=""
	if [ -x "$ROOT/disk/system/bin/linker64" ]; then
		system_src="$ROOT/disk/system"
	elif [ -x "$ROOT/disk/bin/linker64" ]; then
		system_src="$ROOT/disk"
	fi
	[ -n "$system_src" ] || {
		ci_error "android-runtime" "$found: no bin/linker64 in the image; top level is: $(ls -A "$ROOT/disk" | tr '\n' ' ')"
		return 1
	}
	sudo mount --bind "$system_src" "$ROOT/system"
	sudo mount --make-rslave "$ROOT/system" || true

	# vendor/ and product/ ship beside system/ on some images; mount them when present
	# instead of leaving dangling paths inside the chroot.
	local part
	for part in vendor product; do
		if [ -d "$ROOT/disk/$part" ]; then
			sudo mkdir -p "$ROOT/$part"
			sudo mount --bind "$ROOT/disk/$part" "$ROOT/$part" || true
		fi
	done
	[ -x "$ROOT/system/bin/linker64" ] || {
		ci_error "android-runtime" "$found has no /system/bin/linker64 after mounting; wrong image architecture"
		return 1
	}

	# Device paths inside the chroot: files/ keeps its real path so rpath and baked-in
	# configuration resolve without wrappers.
	mkdir -p "$ROOTFS$KODRA_PREFIX" "$ROOTFS$KODRA_HOME" "$ROOTFS$KODRA_PREFIX/tmp"
	sudo mkdir -p "$ROOT$FILES_DIR"
	sudo mount --bind "$ROOTFS$FILES_DIR" "$ROOT$FILES_DIR"
	sudo mount --bind /proc "$ROOT/proc"
	# --rbind, not --bind: /dev/pts is its own mount and a plain bind would hide it, so
	# a PTY could be allocated and never opened. rslave stops the chroot's mounts from
	# propagating back into the runner.
	if sudo mount --rbind /dev "$ROOT/dev"; then
		sudo mount --make-rslave "$ROOT/dev" || true
	elif sudo mount -t devpts -o newinstance,mode=620 devpts "$ROOT/dev/pts"; then
		ci_notice "android-runtime" "/dev bind failed; using an isolated devpts"
	else
		ci_error "android-runtime" "no /dev and no devpts inside the chroot; the node-pty smoke test cannot run"
		return 1
	fi

	# Report the exact bionic build in use, so the evidence names a real linker rather
	# than an assumption.
	local linker_version
	# Report what the chroot can actually execute, not what it contains: this is the
	# difference between "the files are there" and "bionic runs".
	local shell_out
	shell_out="$(sudo chroot "$ROOT" /system/bin/sh -c 'echo ok; uname -m' 2>&1 | tr '\n' ' ' || true)"
	ci_notice "android-runtime" "$found: /system/bin/sh -> ${shell_out:-<no output>}"
}

run() {
	mkdir -p "$ROOTFS$KODRA_PREFIX" "$ROOTFS$KODRA_HOME" "$ROOTFS$KODRA_PREFIX/tmp"
	# Environment mirrors the app: the service sets HOME/PREFIX/TMPDIR/LD_LIBRARY_PATH
	# before spawning the server (see ServerProcess.kt).
	sudo env -i \
		HOME="$KODRA_HOME" \
		PREFIX="$KODRA_PREFIX" \
		TMPDIR="$KODRA_PREFIX/tmp" \
		TERM="${TERM:-xterm-256color}" \
		ANDROID_ROOT=/system \
		ANDROID_DATA=/data \
		PATH="$KODRA_PREFIX/bin:/system/bin" \
		LD_LIBRARY_PATH="$KODRA_PREFIX/lib" \
		NODE_PATH="$KODRA_PREFIX/lib/node_modules" \
		"$(command -v chroot)" "$ROOT" "$@"
}

case "${1:-}" in
install) install ;;
run)
	shift
	run "$@"
	;;
shell)
	shift
	run /system/bin/sh "$@"
	;;
*)
	echo "usage: $0 {install|run <cmd...>|shell -c <script>}" >&2
	exit 2
	;;
esac
