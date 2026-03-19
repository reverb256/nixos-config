/*
 * set-evdev-deadzone - Set kernel-level deadzone for joystick axes
 *
 * Usage: set-evdev-deadzone /dev/input/eventX AXIS_VALUE [AXIS_VALUE]...
 *
 * AXIS_VALUE format: AXIS:DEADZONE
 *   AXIS: 0=ABS_X, 1=ABS_Y, 2=ABS_Z, 3=ABS_RX, 4=ABS_RY, 5=ABS_RZ
 *   DEADZONE: 0-65535 (0 = no deadzone, ~3276 = 5%)
 *
 * Example: set-evdev-deadzone /dev/input/event0 0:2000 1:2000 3:1500 4:1500
 *   Sets deadzone for left stick (X/Y) and right stick (RX/RY)
 *
 * This sets deadzone at the KERNEL LEVEL using EVIOCSABS ioctl.
 * Effects ALL games and applications equally.
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
    unsigned int axis;
    int deadzone;
    char *colon;

    if (argc < 3) {
        fprintf(stderr, "Usage: %s /dev/input/eventX AXIS:DEADZONE [AXIS:DEADZONE]...\n", argv[0]);
        fprintf(stderr, "\nAxis codes:\n");
        fprintf(stderr, "  0 = ABS_X  (left stick X)\n");
        fprintf(stderr, "  1 = ABS_Y  (left stick Y)\n");
        fprintf(stderr, "  2 = ABS_Z  (left trigger)\n");
        fprintf(stderr, "  3 = ABS_RX (right stick X)\n");
        fprintf(stderr, "  4 = ABS_RY (right stick Y)\n");
        fprintf(stderr, "  5 = ABS_RZ (right trigger)\n");
        fprintf(stderr, "\nDeadzone range: 0-65535 (typical: 2000-5000)\n");
        fprintf(stderr, "\nExample:\n");
        fprintf(stderr, "  %s /dev/input/event0 0:2000 1:2000 3:1500 4:1500\n", argv[0]);
        return 1;
    }

    /* Open the event device */
    fd = open(argv[1], O_RDWR);
    if (fd < 0) {
        perror("open");
        fprintf(stderr, "Error: Cannot open %s\n", argv[1]);
        fprintf(stderr, "Try running with sudo\n");
        return 1;
    }

    /* Process each axis:deadzone argument */
    for (int i = 2; i < argc; i++) {
        colon = strchr(argv[i], ':');
        if (!colon) {
            fprintf(stderr, "Error: Invalid format '%s' (expected AXIS:DEADZONE)\n", argv[i]);
            close(fd);
            return 1;
        }

        *colon = '\0';
        axis = atoi(argv[i]);
        deadzone = atoi(colon + 1);

        if (deadzone < 0 || deadzone > 65535) {
            fprintf(stderr, "Error: Deadzone must be 0-65535 (got %d)\n", deadzone);
            close(fd);
            return 1;
        }

        /* Get current axis info */
        if (ioctl(fd, EVIOCGABS(axis), &absinfo) < 0) {
            perror("ioctl(EVIOCGABS)");
            fprintf(stderr, "Error: Cannot get info for axis %u\n", axis);
            fprintf(stderr, "The device may not support this axis\n");
            close(fd);
            return 1;
        }

        /* Set deadzone (flat value) */
        absinfo.flat = deadzone;

        /* Apply the new deadzone */
        if (ioctl(fd, EVIOCSABS(axis), &absinfo) < 0) {
            perror("ioctl(EVIOCSABS)");
            fprintf(stderr, "Error: Cannot set deadzone for axis %u\n", axis);
            fprintf(stderr, "Try running with sudo\n");
            close(fd);
            return 1;
        }

        printf("✅ Set deadzone for axis %u: %d\n", axis, deadzone);
    }

    close(fd);
    return 0;
}
