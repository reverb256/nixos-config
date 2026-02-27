# Work/Cloud Development Module
# AWS, Google Cloud, Firebase, Android Studio, and work tools from XNM1
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # ============================================================================
    # COMMUNICATION
    # ============================================================================
    slack # Messaging platform for work

    # ============================================================================
    # AWS (Amazon Web Services)
    # ============================================================================
    awscli2 # AWS Command Line Interface v2
    aws-sam-cli # AWS Serverless Application Model CLI

    # Session Manager for AWS Systems Manager
    ssm-session-manager-plugin

    # AWS Lambda for Rust
    cargo-lambda

    # ============================================================================
    # GOOGLE CLOUD
    # ============================================================================
    google-cloud-sdk # Google Cloud CLI and tools

    # ============================================================================
    # DATABASES
    # ============================================================================
    postgresql_18 # PostgreSQL client
    pspg # Postgres pager

    # Redis (key-value store)
    # redis  # Already available as a service

    # ============================================================================
    # BUILD TOOLS
    # ============================================================================
    gnumake # GNU Make
    cmake # Cross-platform build system

    # ============================================================================
    # MOBILE DEVELOPMENT
    # ============================================================================
    android-studio # Android development IDE

    # ============================================================================
    # OTHER TOOLS
    # ============================================================================
    redli # Redis-compatible client
  ];
}
