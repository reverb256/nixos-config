# Age-encrypted secrets for NixOS
# Public key for zephyr host
{
  # Host public keys for all systems
  "zephyr-host" = "age175jstqazl7sj20xzuhc4l9qn0xt0ag0nvh2paxkk6veav95se4ysjua4e5";
  "nexus-host" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEldBvJIZYJKHw8pt0/Bx3xhJK4rSrhno0NyHgTtWAaV";
  "forge-host" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFf1b4QFWOV8OI2zC3N6rlE2sHHRzcPGfS7wr/VSoanr";
  "sentry-host" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBK7IznKNG8BJVrPv1dnJBrbFhcmzTKaYSAzVdrXV7Fn";

  # List of all secret files to encrypt with agenix
  secrets = {
    # Claude Code API Key (KAT/StreamLake)
    "claude-api-key.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];

    # Hugging Face API Token
    "hf-token.age".publicKeys = ["zephyr-host" "nexus-host" "forge-host" "sentry-host"];
  };
}
