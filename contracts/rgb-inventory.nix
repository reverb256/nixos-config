{
  schemaVersion = 1;
  interfaceVersion = "1.0";

  # Expected hardware is descriptive inventory, not a claim that Linux can
  # control it. Numeric OpenRGB indices are deliberately excluded: they are
  # runtime observations and are not stable identities.
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
      # Verified from the read-only OpenRGB scan. The Aorus motherboard is
      # intentionally absent because it was not exposed by the backend.
      controlDevices = [
        { hint = "Razer Naga Pro (Wired)"; role = "primary"; matchAll = false; }
      ];
      expected = [
        {
          id = "aorus-x470";
          kind = "motherboard";
          backend = "openrgb";
          hint = "Aorus";
          expectedCount = 1;
          capability = "rgb";
          controlAllowed = false;
          status = "Expected Gigabyte X470 Aorus; SMBus/OpenRGB exposure is pending.";
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

    forge = {
      controlDevices = [ ];
      expected = [
        {
          id = "nvidia-rtx-4060";
          kind = "gpu";
          backend = "pci";
          hint = "RTX 4060";
          expectedCount = 2;
          capability = "visibility-only";
          controlAllowed = false;
          status = "Two NVIDIA RTX 4060 GPUs expected; PCI visibility is reported as a model group.";
        }
        {
          id = "amd-navi10";
          kind = "gpu";
          backend = "drm";
          hint = "Navi 10";
          expectedCount = 2;
          capability = "visibility-only";
          controlAllowed = false;
          status = "Two AMD Navi 10 GPUs expected; amdgpu DRM visibility is currently incomplete.";
        }
      ];
    };

    sentry = {
      controlDevices = [ ];
      expected = [
        {
          id = "amd-navi10";
          kind = "gpu";
          backend = "drm";
          hint = "Navi 10";
          expectedCount = 1;
          capability = "visibility-only";
          controlAllowed = false;
          status = "AMD GPU visibility is tracked separately from RGB support.";
        }
        {
          id = "wraith-cooler-light";
          kind = "cooler";
          backend = "static/unknown";
          hint = "Wraith";
          expectedCount = 1;
          capability = "visibility-only";
          controlAllowed = false;
          status = "Old red Wraith light is not currently exposed as USB, I2C, LED, OpenRGB, or cm-rgb.";
        }
      ];
    };
  };
}
