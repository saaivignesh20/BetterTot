#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/stdio.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "usage: atomic-replace SOURCE DESTINATION\n");
        return 64;
    }

    struct stat destination;
    unsigned int flags;
    const char *operation;
    if (lstat(argv[2], &destination) == 0) {
        flags = RENAME_SWAP;
        operation = "swapped";
    } else if (errno == ENOENT) {
        flags = RENAME_EXCL;
        operation = "moved";
    } else {
        fprintf(stderr, "cannot inspect destination: %s\n", strerror(errno));
        return 1;
    }

    if (renamex_np(argv[1], argv[2], flags) != 0) {
        fprintf(stderr, "atomic replacement failed: %s\n", strerror(errno));
        return 1;
    }

    puts(operation);
    return 0;
}
