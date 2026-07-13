{
  # Garnix hosted cache was shut down on 2026-07-15 (garnix.io → Shopify).
  # The `services.garnix` module was never enabled in this repo and its only
  # consumer (`garnix-password` netrc) is gone, so the module is now a no-op.
  # Kept as a tombstone to avoid dangling imports; safe to delete outright.
  lib,
  ...
}: {
  options.services.garnix = {
    enable = lib.mkEnableOption "Garnix CI/CD cache configuration (DEPRECATED: service shut down 2026-07-15)";
  };
  # Intentionally no config block — code path removed.
}
