{ lib, pkgs, ... }:
{
  # ============================================================================
  # Sentry (10.1.1.140) OUT-OF-BAND MANAGEMENT
  #
  # Hardware reality (2026-08-02 OOM audit): Sentry is a bare-metal Ryzen 1700
  # + RX 5600 XT box with NO IPMI/BMC, NO managed PDU / smart outlet, NOT
  # virtualized. The ONLY remote recovery lever is Wake-on-LAN on the onboard
  # Realtek (r8169) NIC, MAC 70:85:c2:d2:87:bf (persistent name lan0).
  #
  # This module:
  #   - installs wakeonlan so an operator (or the nexus watchdog) can send a
  #     magic packet from the 10.1.1.0/24 segment;
  #   - keeps NM-managed lan0 and pins the MAC so WoL targeting is stable.
  #
  # PREREQUISITE: Sentry's BIOS/UEFI must have "Wake on LAN" / "PME" enabled
  # on the onboard NIC, and the PSU must keep the NIC alive in S5 (soft-off).
  # If WoL is inert, recovery is a PHYSICAL power-cycle at the rack.
  #
  # Live watchdog + WoL sender: hosts/nexus (services.sentry-sentinel).
  # Escalation + runbook: docs/incidents/2026-08-02-sentry-down-oob.md
  # ============================================================================

  # wakeonlan on the host so the magic packet can be emitted locally if needed
  environment.systemPackages = with pkgs; [ wakeonlan ];

  # Ensure the NIC is NM-managed and the known MAC is pinned (link already
  # renamed to lan0 via modules/system/interface-naming.nix). WoL itself is
  # enabled in firmware; this only guarantees the tooling + stable address.
  networking.networkmanager = {
    enable = true;
    # No per-MAC NM setting is required beyond the persistent link name;
    # WoL is firmware-gated. Documented here for audit traceability.
  };

  # Persist the OOB facts in the active config so any future operator sees
  # the recovery contract inline rather than hunting through docs.
  environment.etc."oob/sentry.txt".text = ''
    Host:        sentry (10.1.1.140)
    NIC MAC:     70:85:c2:d2:87:bf  (persistent name: lan0, driver r8169)
    OOB method:  Wake-on-LAN (magic packet from 10.1.1.0/24)
    Requires:    BIOS "Wake on LAN"/"PME" enabled + PSU keeps NIC alive in S5
    If WoL inert: PHYSICAL power-cycle at rack (no IPMI/BMC/PDU present)
    Watchdog:    nexus service sentry-sentinel (alerts + sends WoL)
    Runbook:     docs/incidents/2026-08-02-sentry-down-oob.md
  '';
}
