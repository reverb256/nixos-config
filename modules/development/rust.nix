# Rust Development Module
# Advanced Rust toolchain with rust-overlay and comprehensive cargo tools
{
  pkgs,
  inputs,
  ...
}: {
  # Add rust-overlay to nixpkgs
  nixpkgs.overlays = [
    inputs.rust-overlay.overlays.default
  ];

  # System packages for Rust development
  environment.systemPackages = with pkgs; [
    # Rust toolchain from rust-overlay
    (pkgs.rust-bin.selectLatestNightlyWith (
      toolchain:
        toolchain.default.override {
          extensions = [
            "rust-src"
            "rust-analyzer"
            "rustfmt"
            "clippy"
          ];
        }
    ))

    # Essential build tools
    pkg-config
    rustc
    cargo

    # LSP and language servers
    rust-analyzer
    taplo # TOML formatter and LSP

    # Cargo tools - Build automation
    bacon # Background cargo check
    cargo-watch # Watch for changes and run commands
    cargo-nextest # Better test runner
    cargo-zigbuild # Cross-compilation with zig

    # Cargo tools - Dependency management
    cargo-edit # Add/remove dependencies
    cargo-outdated # Check for outdated dependencies
    cargo-update # Update dependencies
    cargo-bloat # Find largest dependencies

    # Cargo tools - Code quality
    cargo-deny # Dependency linting
    cargo-audit # Security audit
    cargo-spellcheck # Spell check documentation
    cargo-udeps # Find unused dependencies
    cargo-unused-features # Find unused features

    # Cargo tools - Development helpers
    cargo-expand # Macro expansion
    cargo-modules # List modules
    cargo-feature # Feature management

    # Cargo tools - Testing and coverage
    cargo-tarpaulin # Code coverage
    cargo-nextest

    # Cross-compilation
    zig # Required for cargo-zigbuild

    # REPL and evaluation
    evcxr # Rust REPL
  ];

  # Environment variables for Rust development
  environment.sessionVariables = {
    # Enable Rust compiler optimizations
    RUSTFLAGS = "-C target-cpu=native";
  };
}
