# git — the binary the built-in Git extension runs. Not a reimplementation: the
# extension shells out to this and parses its output, so it must be real git.
#
# NO_OPENSSL/NO_CURL for now: TLS git needs OpenSSL and libcurl in the prefix,
# which arrive in a later package of this same stage. Without them git works on
# local and file:// repositories and reports the gap explicitly instead of
# pretending https works.
PKG_VERSION=2.47.1
# kernel.org is the canonical source and publishes sha256sums.txt alongside it.
PKG_URL="https://www.kernel.org/pub/software/scm/git/git-$PKG_VERSION.tar.gz"
# kernel.org publishes sha256sums.txt next to the tarballs, but it is not reachable
# from the development sandbox; this is the digest the build observed over TLS
# (`build.sh pin`) and is enforced from then on.
PKG_SHA256=f4c4e98667800585d218dfdf415eb72f73baa7abcac4569e2ce497970f8d6665

# What this package must leave in the prefix; build.sh fails the build if any of it
# is missing, so a wrong DESTDIR cannot pass as success.
PKG_ARTIFACTS="bin/git libexec/git-core/git-commit"

build() {
	local archive
	archive="$(pkg_fetch "$PKG_URL" "$PKG_SHA256")" || return 1
	pkg_extract "$archive" "$PKG_DIR" >/dev/null || return 1
	cd "$PKG_DIR/git-$PKG_VERSION" || return 1

	GIT_BUILD_SHELL="${GIT_BUILD_SHELL:-/bin/bash}"
	[ -x "$GIT_BUILD_SHELL" ] || {
		ci_error "git" "$GIT_BUILD_SHELL is not executable; it is needed only during the build"
		return 1
	}

	# NO_PTHREADS: bionic has no POSIX thread cancellation — pthread.h declares neither
	# PTHREAD_CANCEL_DISABLE nor pthread_setcancelstate, and git uses both around fork.
	# That makes git single-threaded on Android, which is a real difference and is
	# recorded as such rather than papered over.
	# PTHREAD_LIBS and NEEDS_LIBRT: empty because bionic keeps the pthread entry points
	# and clock_gettime in libc and ships neither libpthread nor librt, so git's Linux
	# defaults (-lpthread, -lrt) fail at link time.
	#
	# DESTDIR: git honours it exactly like an autotools package, so 'prefix' stays the
	# device path and the files are staged under the root filesystem.
	#
	# SHELL_PATH: git's Makefile runs $(SHELL_PATH) -c while parsing and refuses to continue unless a
	# modern shell answers. SHELL_PATH cannot point at the prefix during the build: the
	# staged bash is an Android binary whose interpreter is /system/bin/linker64, so the
	# build host cannot execute it at all. The build therefore uses the host shell and
	# the installed scripts are rewritten afterwards to the device path — git bakes
	# SHELL_PATH into them, and /bin/bash does not exist on Android.
	make -j"$(nproc)" \
		CC="$CC" AR="$AR" RANLIB="$RANLIB" \
		CFLAGS="$ANDROID_CFLAGS -O2 -I$KODRA_PREFIX/include" \
		LDFLAGS="$ANDROID_LDFLAGS -L$KODRA_PREFIX/lib" \
		prefix="$KODRA_PREFIX" \
		DESTDIR="$KODRA_ROOTFS" \
		gitexecdir="$KODRA_PREFIX/libexec/git-core" \
		template_dir="$KODRA_PREFIX/share/git-core/templates" \
		NO_GETTEXT=1 \
		NO_TCLTK=1 \
		NO_PERL=1 \
		NO_PYTHON=1 \
		NO_EXPAT=1 \
		NO_ICONV=1 \
		NO_OPENSSL=1 \
		NO_CURL=1 \
		NO_LIBPCRE=1 \
		NO_PTHREADS=1 \
		PTHREAD_LIBS= \
		NEEDS_LIBRT= \
		NO_INSTALL_HARDLINKS=1 \
		SHELL_PATH="$GIT_BUILD_SHELL" \
		INSTALL_SYMLINKS=1 \
		install || return 1

	_rescript_to_device_shell
}

# Every installed script that names the build host's shell is rewritten to the prefix's
# bash. Done as a separate step so it is visible in the recipe rather than hidden in a
# flag, and 'verify' re-checks it inside the Android userland.
_rescript_to_device_shell() {
	local f changed=0
	while IFS= read -r f; do
		sed -i "1s|^#!${GIT_BUILD_SHELL}\$|#!$KODRA_PREFIX/bin/bash|" "$f"
		changed=$((changed + 1))
	done < <(grep -rl "^#!${GIT_BUILD_SHELL}\$" "$KODRA_ROOTFS$KODRA_PREFIX/bin" \
		"$KODRA_ROOTFS$KODRA_PREFIX/libexec" 2>/dev/null)
	log_git "rewrote $changed script shebang(s) to $KODRA_PREFIX/bin/bash"
}

log_git() { printf '[git] %s\n' "$*" >&2; }
