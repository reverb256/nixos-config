{
  inputs,
  _final,
  prev,
}: {
  gputemps = prev.callPackage ../packages/gputemps.nix {};
  # Nexus cluster ingress uses the repository's Caddy build with rate-limit,
  # security, and cache modules. Expose it through the normal pkgs overlay so
  # host modules can depend on pkgs.caddy-with-modules declaratively.
  caddy-with-modules = prev.callPackage ../pkgs/caddy-with-modules {};
  lmstudio = prev.callPackage ../packages/lmstudio.nix {};
  peakminer = prev.callPackage ../pkgs/peakminer.nix {};
  secretspec = prev.callPackage ../pkgs/secretspec {};
  haven-desktop = prev.callPackage ../packages/haven-desktop.nix {};
  kokoro-tts = prev.callPackage ../packages/kokoro-tts.nix {};
  chatterbox-tts = prev.callPackage ../packages/chatterbox-tts.nix {};
  # Proton-GE-RTSP — Proton-GE fork with hardware video decode (h264/RTMP)
  # for VRChat in-world video players. Consumed via
  # programs.steam.extraCompatPackages only (see modules/gaming/gaming-vr-unlock.nix).
  proton-ge-rtsp = prev.callPackage ../packages/proton-ge-rtsp.nix {};
  niri-hdr = prev.callPackage ../pkgs/niri-hdr.nix {inherit (prev) niri-unstable;};
  assimp = prev.assimp.overrideAttrs (_old: {doCheck = false;});
  # 2026-08-04: cups notifier-permission fix REMOVED from build phase.
  # The build-time `overrideAttrs { postInstall = chmod notifier dirs }` forked
  # the cups derivation from the cached upstream path. Since cups is a transitive
  # dep of the Qt6/v4l-utils/gtk3/mesa graphics stack, this ONE override caused
  # the entire desktop graphics closure to recompile from source on every build
  # (mesa ~5662 units) because cups was homelab-unique and absent from cache.nixos.org.
  # The runtime fix is ALREADY covered declaratively by the tmpfiles rule in
  # modules/system/boot-error-fixes.nix ("Z+ .../notifier/dbus 0555 root root").
  # Removing the override lets cups substitute from cache.nixos.org, un-forking
  # mesa/gtk3/qtbase/v4l-utils. Verified: cups/mesa drv now == cached path;
  # mesa narinfo HTTP 200. If cupsd ever complains about notifier ownership,
  # extend the tmpfiles rule instead of reintroducing a build-phase fork.
  dufs = prev.dufs.overrideAttrs (old: {
    doCheck = false;
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [prev.cacert];
  });
  herdr = prev.callPackage ../packages/herdr.nix {};
  llama-cpp = prev.callPackage ../packages/llama-cpp.nix {
    cudaSupport = true;
    inherit (prev) cudaPackages;
  };
  # PrismML bonsai-ml fork + CUDA + Vulkan in one binary — the fleet-wide
  # package (Q1_0/Q2_0 repack, DSpark, CPU-MoE). Real derivation, so colmena
  # copies it and GC keeps it (unlike string binaryStorePath refs).
  llama-cpp-unified = prev.callPackage ../packages/llama-cpp.nix {
    useFork = true;
    cudaSupport = true;
    vulkanSupport = true;
    cudaArchitectures = "86;89";
    inherit (prev) cudaPackages;
  };
  # AMD-only variant of the unified fork: Vulkan backend, CUDA disabled
  # (libcuda DT_NEEDED hard-link crashes the loader on AMD-only hosts).
  llama-cpp-unified-vulkan = prev.callPackage ../packages/llama-cpp.nix {
    useFork = true;
    cudaSupport = false;
    vulkanSupport = true;
  };
  llama-cpp-ik = prev.callPackage ../packages/llama-cpp-ik.nix {};
  llama-cpp-rocm = prev.callPackage ../packages/llama-cpp-rocm.nix {};
  llama-cpp-vulkan = prev.callPackage ../packages/llama-cpp-vulkan.nix {};
  llama-cpp-vulkan-nocuda = prev.callPackage ../packages/llama-cpp-vulkan-nocuda.nix {};
  nixos-cluster-mcp = prev.callPackage ../packages/nixos-cluster-mcp {};
  switchyard-server = prev.callPackage ../pkgs/switchyard-server {};
  # memlawb encrypted-memory server (Bun app). Exposed as pkgs.memlawb so the
  # host module (modules/services/memlawb-server.nix) can reference
  # pkgs.memlawb/bin/memlawb-server. Source is the pinned `memlawb` flake input.
  memlawb = prev.callPackage ../pkgs/memlawb.nix { inherit (inputs) memlawb; };
  # omarchy UX layer (themes, router, plugins, shell, dots) — verbatim
  # Tier-1 port. Source is the pinned `omarchy` flake input (flake=false),
  # installed to $out/share/omarchy + bin/omarchy* symlink farm by
  # pkgs/omarchy.nix. Consumed by modules/omarchy/default.nix.
  omarchy = prev.callPackage ../pkgs/omarchy.nix { inherit (inputs) omarchy; };
  # qml-niri — third-party `import Niri` QML plugin (Phase 2, #657). The
  # plugin itself installs to $out/lib/qt-6/qml/Niri (its default.nix already
  # derives the qtQmlPrefix from qt6), so adding it to quickshell's buildInputs
  # makes wrapQtAppsHook put it on QML_IMPORT_PATH automatically. This is
  # quickshell with the Niri plugin wired in, NOT the nonexistent
  # `Quickshell.Niri` native module #657 assumed.
  qml-niri = inputs.qml-niri.packages.x86_64-linux.default;
  quickshell-niri = prev.quickshell.overrideAttrs (old: {
    buildInputs = (old.buildInputs or []) ++ [inputs.qml-niri.packages.x86_64-linux.default];
  });
  privacy-filter = prev.callPackage ../packages/privacy-filter.nix {
    transformers-dev = prev.callPackage ../packages/transformers-dev.nix {};
  };
  hermes-chat = prev.callPackage ../packages/hermes-chat.nix {};
  # nixpkgs dropped node20 externals (EOL) — only node24 ships in
  # github-runner's lib/externals. GitHub Actions built pre-2025 (e.g.
  # codeql-action/upload-sarif@v3) resolve their interpreter as
  # externals/node20/bin/node and crash with "No such file or directory"
  # on the self-hosted runner. node24 is a drop-in superset for the
  # action host, so symlink node20 -> node24.
  github-runner-with-node20 = prev.github-runner.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        if [ -d "$out/lib/externals/node24" ] && [ ! -e "$out/lib/externals/node20" ]; then
          ln -s node24 "$out/lib/externals/node20"
        fi
      '';
  });
}
