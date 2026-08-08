# Fleet RGB Inventory and Control Plane

**Date:** 2026-08-08
**Status:** Design ready for review

## Context

The cluster has heterogeneous lighting hardware:

- **Zephyr:** ENE/G.Skill-style DRAM, EVGA RTX 3090 RGB, MSI Mystic Light,
  Corsair Lighting Node Pro, Corsair H115i PRO RGB, and Razer Naga Pro.
- **Nexus:** Gigabyte X470 Aorus motherboard and Razer Naga Pro. The live
  OpenRGB scan currently exposes only the mouse.
- **Forge:** four intended GPUs: two NVIDIA RTX 4060s and two AMD Navi 10
  cards. PCI sees all four, but the AMD cards currently have no DRM nodes;
  OpenRGB sees no devices.
- **Sentry:** AMD Navi 10 GPU and an older red Wraith cooler light. The live
  system does not expose OpenRGB, cm-rgb, a cooler USB controller, or a custom
  LED class.

The current configuration has multiple OpenRGB ownership paths and uses
host-specific numeric device indices in shared temperature-reactive logic.
Numeric indices are not stable identities and must not be used as the fleet
inventory source of truth.

## Goals

1. Make expected RGB-capable hardware visible per host.
2. Compare expected hardware with live backend discovery.
3. Export health and discrepancy metrics through the existing node-exporter
   textfile collector.
4. Keep RGB writes disabled unless a device is explicitly allowlisted.
5. Ensure each host has at most one OpenRGB SDK server owner.
6. Keep fan/PWM control separate and BIOS-owned by default.
7. Represent unsupported or currently invisible hardware honestly.

## Non-goals

- No central RGB API or remote RGB write service in this phase.
- No automatic firmware updates, controller initialization, or device writes.
- No software fan curves or PWM changes.
- No assumption that an illuminated component is Linux-addressable.
- No automatic correction of Forge's missing AMD DRM nodes in the RGB phase.

## Source of truth

Add `contracts/rgb-inventory.nix` with a typed, declarative inventory. Each
host entry contains:

- expected devices with stable matching hints (`kind`, `vendor`, `model`
  fragments, optional USB/PCI IDs);
- backend (`openrgb`, `openrazer`, `liquidctl`, `cm-rgb`, `pci`, `drm`, or
  `static/unknown`);
- capability (`rgb`, `telemetry`, or `visibility-only`);
- `controlAllowed = false` initially for every device;
- a human-readable status note for known gaps.

OpenRGB numeric indices are runtime observations only and are never committed
as identities. Per-host control allowlists remain empty until a read-only scan
confirms stable matching.

## Host inventory entries

The initial contract records the known hardware without claiming support:

- Zephyr: ENE/G.Skill DRAM, EVGA RTX 3090, MSI Mystic Light, Corsair Lighting
  Node Pro, Corsair H115i PRO RGB, and Razer Naga Pro.
- Nexus: Gigabyte X470 Aorus and Razer Naga Pro; Aorus control is pending
  SMBus/controller exposure.
- Forge: two NVIDIA RTX 4060 and two AMD Navi 10 GPUs; RGB capability is
  pending device discovery, while PCI visibility is expected for all four.
- Sentry: AMD Navi 10 GPU plus an expected old Wraith light marked
  `static/unknown` until a controller is detected.

## Runtime inventory service

Add `modules/services/rgb-inventory.nix`, enabled on hosts through the shared
RGB profile. It provides:

- `rgb-inventory` — read-only JSON/text report command;
- a oneshot service and timer that refresh `/var/lib/rgb-inventory/report.json`;
- Prometheus textfile output at
  `/var/lib/prometheus/node-exporter/textfile-collector/rgb_inventory.prom`.

The collector may invoke discovery/status commands but must not invoke RGB
write operations, OpenRGB profiles, `liquidctl initialize`, or fan/PWM writes.
It records command availability, service state, OpenRGB device listing,
liquidctl listing/status availability, PCI GPU visibility, DRM-card visibility,
and allowlist matches. Secret contents are never read or emitted.

## Metrics

Metrics use stable labels (`host`, `backend`, `device_kind`, `device_hint`) and
avoid exposing serials or volatile OpenRGB numeric indices as identity labels.

- `rgb_inventory_expected_info{...} 1`
- `rgb_inventory_detected{...} 0|1`
- `rgb_inventory_control_allowed{...} 0|1`
- `rgb_inventory_backend_available{backend="..."} 0|1`
- `rgb_inventory_backend_active{backend="..."} 0|1`
- `rgb_inventory_visibility_gap{...} 0|1`
- `rgb_inventory_scan_success 0|1`
- `rgb_inventory_scan_timestamp_seconds <unix time>`

A device can be detected but not controllable. A GPU can be PCI-visible but
not DRM-visible. These are intentionally separate states.

## OpenRGB ownership

The native NixOS `services.hardware.openrgb` module is the sole OpenRGB SDK
server owner. The older Corsair `autoStartRgb` service must remain disabled or
be removed from the active path; status scripts must not stop and restart the
server. OpenRGB clients may be used for future explicit control, but the
inventory service is read-only.

The existing temperature-reactive service remains disabled for Nexus through
an explicit empty device allowlist. Other hosts retain legacy mappings only
until their stable identity migration is completed; no new device is added to
an allowlist in this phase.

## Known discrepancy handling

- Forge's two AMD GPUs remain in the expected inventory even while their
  `amdgpu` driver produces no DRM cards. The RGB report exposes this as a
  visibility gap and does not attempt to fix it.
- Sentry's old Wraith red light is reported as expected-but-unaddressable until
  a USB, I2C, LED, or supported OpenRGB/cm-rgb controller appears.
- Nexus's Aorus board is expected but not detected; the report identifies the
  missing SMBus/OpenRGB exposure.

## Validation

- Parse all changed Nix files.
- Evaluate the inventory contract and focused test.
- Verify the generated service is read-only by source inspection: no write
  verbs, OpenRGB profiles, device-index writes, `liquidctl initialize`, or
  `pwm*` writes.
- Run the inventory command in a controlled read-only mode where available.
- Run `nix flake check --no-build --no-write-lock-file` after the existing
  dendritic worktree snapshot issue is resolved; until then report that
  environmental blocker separately.
- Do not deploy or change RGB state as part of implementation validation.
