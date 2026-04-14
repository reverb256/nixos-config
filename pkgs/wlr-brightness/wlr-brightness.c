/*
 * wlr-brightness — gamma ramp brightness control for Wayland compositors
 * that implement zwlr_gamma_control_v1 (e.g. niri, Sway, Hyprland).
 *
 * Usage:
 *   wlr-brightness                      # list outputs and current brightness
 *   wlr-brightness set <output> <0-100> # set brightness for an output
 *   wlr-brightness set-all <0-100>      # set brightness for all outputs
 *   wlr-brightness get <output>         # get current brightness
 *
 * Build: gcc -o wlr-brightness wlr-brightness.c -lwayland-client
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <errno.h>
#include <wayland-client.h>

/* Inline protocol definitions — no external XML dependency */

/* wl_output */
static const struct wl_interface *wl_output_interface = NULL;

/* zwlr_gamma_control_manager_v1 */
static const struct wl_interface zwlr_gamma_control_manager_v1_interface;
static const struct wl_interface zwlr_gamma_control_v1_interface;

/* Registry name → output mapping */
#define MAX_OUTPUTS 16
static struct {
    struct wl_output *output;
    char name[256];
    char desc[512];
    int scale;
    int gamma_size;
    struct zwlr_gamma_control_v1 *gamma;
    uint32_t registry_name;
    double brightness; /* 0.0 - 1.0 */
    int initialized;
} outputs[MAX_OUTPUTS];
static int n_outputs = 0;
static int done = 0;

/* Forward declarations */
struct zwlr_gamma_control_manager_v1;
struct zwlr_gamma_control_v1;

/* We need the actual wayland-protocol C headers.
 * Instead of generating them, we'll use raw wayland-client protocol binding.
 * This requires knowing the interface names and method/event signatures.
 */

/* Actually, let's use a simpler approach: shell out to wayland-info/wlr-randr
 * for discovery, and use the raw protocol for gamma control.
 *
 * Even simpler: just use a Python script that talks the protocol via
 * wayland-client bindings or raw socket. But for now, let's do it properly.
 */

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "wlr-brightness — gamma ramp brightness control\n");
        fprintf(stderr, "Usage:\n");
        fprintf(stderr, "  wlr-brightness list                    # list outputs\n");
        fprintf(stderr, "  wlr-brightness set <output> <0-100>    # set brightness\n");
        fprintf(stderr, "  wlr-brightness set-all <0-100>         # set all outputs\n");
        fprintf(stderr, "  wlr-brightness get <output>            # get brightness\n");
        return 1;
    }

    /* This is a placeholder — the actual implementation needs
     * generated protocol headers from the XML.
     * For now we use the shell-script approach below. */
    fprintf(stderr, "See wlr-brightness.sh for the working implementation\n");
    return 1;
}
