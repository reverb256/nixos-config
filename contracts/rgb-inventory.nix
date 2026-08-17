{
  schemaVersion = 1;
  interfaceVersion = "1.0";

  # Expected hardware is descriptive inventory, not a claim that Linux can
  # control it. Numeric OpenRGB indices are deliberately excluded: they are
  # runtime observations and are not stable identities.
  #
  # All devices appear 2x in OpenRGB scans (the SDK returns each controller
  # once per detected bus). matchAll = true is intentional everywhere unless
  # noted.
  hosts = {
    zephyr = {
      # Verified from the read-only OpenRGB scan on 2026-08-08. ENE DRAM
      # appears twice, so matchAll is intentional; all other identities are
      # unique. These are RGB devices only, not fan/PWM paths.
      controlDevices = [
        { hint = "ENE DRAM"; role = "primary"; matchAll = true; }
        { hint = "EVGA GeForce RTX 3090 XC3 Ultra Hybrid"; role = "secondary"; matchAll = false; }
        { hint = "MSI MAG X570 TOMAHAWK WIFI"; role = "primary"; matchAll = false; }
        { hint = "Corsair Lighting Node Pro"; role = "secondary"; matchAll = false; }
        { hint = "Corsair H115i PRO RGB"; role = "secondary"; matchAll = false; }
        { hint = "Razer Naga Pro (Wireless)"; role = "secondary"; matchAll = false; }
        { hint = "Razer Naga Pro (Wired)"; role = "secondary"; matchAll = false; }
      ];
      expected = [
        {
          id = "gskill-dram";
          kind = "dram";
          backend = "openrgb";
          hint = "ENE";
          expectedCount = 2;
          capability = "rgb";
          controlAllowed = true;
          status = "Verified OpenRGB identity; Stylix control is explicitly allowlisted for both DRAM devices.";
        }
        {
          id = "evga-rtx-3090";
          kind = "gpu";
          backend = "openrgb";
          hint = "EVGA";
          expectedCount = 1;
          capability = "rgb";
          controlAllowed = true;
          status = "Verified OpenRGB identity; Stylix control is explicitly allowlisted.";
        }
        {
          id = "msi-mystic-light";
          kind = "motherboard";
          backend = "openrgb";
          hint = "MSI";
          expectedCount = 1;
          capability = "rgb";
          controlAllowed = true;
          status = "Verified OpenRGB identity; Stylix control is explicitly allowlisted.";
        }
        {
          id = "corsair-lighting-node";
          kind = "controller";
          backend = "openrgb";
          hint = "Corsair Lighting Node";
          expectedCount = 1;
          capability = "rgb";
          controlAllowed = true;
          status = "Verified OpenRGB identity; Stylix control is explicitly allowlisted.";
        }
        {
          id = "corsair-h115i";
          kind = "aio";
          backend = "openrgb";
          hint = "Corsair H115i";
          expectedCount = 1;
          capability = "rgb";
          controlAllowed = true;
          status = "Verified OpenRGB identity; RGB control is allowlisted; fan/pump telemetry remains separate.";
        }
        {
          id = "razer-naga";
          kind = "mouse";
          backend = "openrgb";
          hint = "Razer Naga Pro";
          expectedCount = 1;
          capability = "rgb";
          controlAllowed = true;
          status = "Verified OpenRGB identity; Stylix control is explicitly allowlisted.";
        }
      ];
    };

    nexus = {
      # Aorus X470 RGB Fusion 2 SMBus IS now detected (i2c-6, address 0x68).
      # Both devices appear 2x in OpenRGB scans — matchAll=true intentional.
      controlDevices = [
        { hint = "X470 AORUS ULTRA GAMING-CF"; role = "primary"; matchAll = true; }
        { hint = "Razer Naga Pro (Wired)"; role = "secondary"; matchAll = true; }
      ];
      expected = [
        {
          id = "aorus-x470";
          kind = "motherboard";
          backend = "openrgb";
          hint = "X470 AORUS";
          expectedCount = 1;
          capability = "rgb";
          controlAllowed = true;
          status = "Aorus X470 RGB Fusion 2 SMBus now detected by OpenRGB; Stylix control allowlisted (matchAll=true for dual listing).";
        }
        {
          id = "razer-naga";
          kind = "mouse";
          backend = "openrgb";
          hint = "Razer Naga Pro";
          expectedCount = 1;
          capability = "rgb";
          controlAllowed = true;
          status = "Verified OpenRGB identity; Stylix control allowlisted (matchAll=true for dual listing).";
        }
      ];
    };

    forge = {
      # Sapphire RX 5700 XT Nitro+ GPUs ARE detected (Nitro Glow V3 via AMDGPU
      # DM i2c OEM bus, address 0x28). Both GPUs appear 2x — matchAll=true.
      controlDevices = [
        { hint = "Sapphire Radeon RX 5700 XT Nitro+"; role = "primary"; matchAll = true; }
      ];
      expected = [
        {
          id = "sapphire-rx5700xt";
          kind = "gpu";
          backend = "openrgb";
          hint = "Sapphire Radeon RX 5700 XT Nitro+";
          expectedCount = 2;
          capability = "rgb";
          controlAllowed = true;
          status = "Sapphire Nitro Glow V3 GPUs detected via AMDGPU DM i2c OEM bus; Stylix control allowlisted (matchAll=true).";
        }
        {
          id = "nvidia-rtx-4060";
          kind = "gpu";
          backend = "pci";
          hint = "RTX 4060";
          expectedCount = 2;
          capability = "visibility-only";
          controlAllowed = false;
          status = "Two NVIDIA RTX 4060 GPUs expected; PCI visibility reported. OpenRGB GPU support limited to ASUS/Gigabyte.";
        }
      ];
    };

    sentry = {
      # Corsair Scimitar Pro RGB (PID 0x1B3E) IS supported by OpenRGB.
      controlDevices = [
        { hint = "Corsair Corsair Gaming SCIMITAR PRO RGB Mouse"; role = "primary"; matchAll = false; }
      ];
      expected = [
        {
          id = "corsair-scimitar";
          kind = "mouse";
          backend = "openrgb";
          hint = "Corsair Corsair Gaming SCIMITAR PRO RGB Mouse";
          expectedCount = 1;
          capability = "rgb";
          controlAllowed = true;
          status = "Corsair Scimitar Pro RGB (PID 0x1B3E) is supported by OpenRGB CorsairPeripheralController; Stylix control allowlisted.";
        }
        {
          id = "amd-navi10";
          kind = "gpu";
          backend = "drm";
          hint = "Navi 10";
          expectedCount = 1;
          capability = "visibility-only";
          controlAllowed = false;
          status = "AMD RX 5600 XT GPU visibility tracked; RGB control not exposed via DRM.";
        }
      ];
    };
  };
}
