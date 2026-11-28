/*
 * forkpty(3)/openpty(3) for bionic.
 *
 * glibc keeps these in libutil and Android has no libutil, so a node-pty built
 * for Android fails to link without them. bionic does provide the primitives —
 * posix_openpt, grantpt, unlockpt, ptsname — so this header builds the same
 * pair on top of them.
 *
 * The build only force-includes this file after a compile probe proves the
 * platform lacks the symbols, so a bionic that grows them is used untouched.
 * The functions are static: exactly one translation unit includes this, and a
 * duplicated external definition would break the addon link.
 */
#ifndef KODRA_NODE_PTY_ANDROID_H
#define KODRA_NODE_PTY_ANDROID_H

#if defined(__ANDROID__)

#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

static int kodra_openpty(int *amaster, int *aslave, char *name,
			 const struct termios *termp, const struct winsize *winp) {
	int master, slave;
	const char *slaveName;

	master = posix_openpt(O_RDWR | O_NOCTTY);
	if (master < 0) {
		return -1;
	}
	if (grantpt(master) != 0 || unlockpt(master) != 0) {
		close(master);
		return -1;
	}
	slaveName = ptsname(master);
	if (slaveName == NULL) {
		close(master);
		return -1;
	}
	if (name != NULL) {
		strncpy(name, slaveName, 127);
		name[127] = '\0';
	}
	slave = open(slaveName, O_RDWR | O_NOCTTY);
	if (slave < 0) {
		close(master);
		return -1;
	}
	if (termp != NULL && tcsetattr(slave, TCSAFLUSH, termp) != 0) {
		close(master);
		close(slave);
		return -1;
	}
	if (winp != NULL && ioctl(slave, TIOCSWINSZ, winp) < 0) {
		close(master);
		close(slave);
		return -1;
	}
	*amaster = master;
	*aslave = slave;
	return 0;
}

static pid_t kodra_forkpty(int *amaster, char *name,
			   const struct termios *termp, const struct winsize *winp) {
	int master, slave;
	pid_t pid;

	if (kodra_openpty(&master, &slave, name, termp, winp) < 0) {
		return -1;
	}
	pid = fork();
	if (pid < 0) {
		close(master);
		close(slave);
		return -1;
	}
	if (pid == 0) {
		close(master);
		/* New session, then take the slave as the controlling terminal: this is
		 * what makes the child look like a login shell to job control. */
		setsid();
		ioctl(slave, TIOCSCTTY, (char *)0);
		dup2(slave, STDIN_FILENO);
		dup2(slave, STDOUT_FILENO);
		dup2(slave, STDERR_FILENO);
		if (slave > STDERR_FILENO) {
			close(slave);
		}
		return 0;
	}
	close(slave);
	if (amaster != NULL) {
		*amaster = master;
	} else {
		close(master);
	}
	return pid;
}

#endif /* __ANDROID__ */
#endif /* KODRA_NODE_PTY_ANDROID_H */
