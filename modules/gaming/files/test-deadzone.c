/*
 * test-deadzone - Verify if kernel deadzone is working
 *
 * Compiles with: gcc -o test-deadzone test-deadzone.c
 * Usage: ./test-deadzone /dev/input/event29
 *
 * This reads the current axis values and checks if deadzone is applied
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/input.h>
#include <errno.h>
#include <sys/ioctl.h>

int main(int argc, char *argv[]) {
    int fd;
    struct input_absinfo absinfo;

    if (argc < 2) {
        fprintf(stderr, "Usage: %s /dev/input/eventX\n", argv[1]);
        return 1;
    }

    fd = open(argv[1], O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    printf("Checking deadzone settings for %s\n\n", argv[1]);

    // Check left stick X (axis 0)
    if (ioctl(fd, EVIOCGABS(0), &absinfo) >= 0) {
        printf("Axis 0 (Left Stick X):\n");
        printf("  Current value: %d\n", absinfo.value);
        printf("  Deadzone (flat): %d\n", absinfo.flat);
        printf("  Minimum: %d, Maximum: %d\n", absinfo.minimum, absinfo.maximum);
        printf("  Fuzz: %d\n\n", absinfo.fuzz);
    }

    // Check left stick Y (axis 1)
    if (ioctl(fd, EVIOCGABS(1), &absinfo) >= 0) {
        printf("Axis 1 (Left Stick Y):\n");
        printf("  Current value: %d\n", absinfo.value);
        printf("  Deadzone (flat): %d\n", absinfo.flat);
        printf("  Minimum: %d, Maximum: %d\n", absinfo.minimum, absinfo.maximum);
        printf("  Fuzz: %d\n\n", absinfo.fuzz);
    }

    // Check right stick X (axis 3)
    if (ioctl(fd, EVIOCGABS(3), &absinfo) >= 0) {
        printf("Axis 3 (Right Stick X):\n");
        printf("  Current value: %d\n", absinfo.value);
        printf("  Deadzone (flat): %d\n", absinfo.flat);
        printf("  Minimum: %d, Maximum: %d\n", absinfo.minimum, absinfo.maximum);
        printf("  Fuzz: %d\n\n", absinfo.fuzz);
    }

    // Check right stick Y (axis 4)
    if (ioctl(fd, EVIOCGABS(4), &absinfo) >= 0) {
        printf("Axis 4 (Right Stick Y):\n");
        printf("  Current value: %d\n", absinfo.value);
        printf("  Deadzone (flat): %d\n", absinfo.flat);
        printf("  Minimum: %d, Maximum: %d\n", absinfo.minimum, absinfo.maximum);
        printf("  Fuzz: %d\n\n", absinfo.fuzz);
    }

    close(fd);
    return 0;
}
