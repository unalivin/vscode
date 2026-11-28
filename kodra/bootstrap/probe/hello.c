/*
 * Toolchain probe. Not shipped: it exists so CI fails loudly if the compiler ever
 * stops producing Android binaries (wrong interpreter, glibc symbol versions, host
 * ABI note). Prints a fixed line the smoke test compares against.
 */
#include <stdio.h>
#include <unistd.h>

int main(void) {
	printf("kodra-probe ok uid=%u page=%ld\n", (unsigned)getuid(), sysconf(_SC_PAGESIZE));
	return 0;
}
