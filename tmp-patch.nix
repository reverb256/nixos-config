  # Host-specific CPU/GPU optimization for llama.cpp (Zen1 + Ada: RTX 4060)
  nixpkgs.config = {
    allowUnfree = true;
    packageOverrides = pkgs: {
      llama-cpp-turboquant = pkgs.llama-cpp-turboquant.overrideAttrs (old: {
        CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3";
      });
      llama-cpp = pkgs.llama-cpp.override {
        cudaSupport = true;
      };
      llama-cpp-cuda = pkgs.llama-cpp.override {
        cudaSupport = true;
      };
      llama-cpp-vulkan = pkgs.llama-cpp-vulkan.overrideAttrs (old: {
        CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3";
      });
    };
  };
