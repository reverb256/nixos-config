# AI Inference Router - Intelligent request classification and routing
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ai-inference;
  inherit (lib) mkIf mkDefault;

  # Router logic (embedded in gateway, but config is here)
  # The routing rules are applied in the gateway before forwarding to backend

  # Token estimation utility - wrapped in symlinkJoin for proper package structure
  tokenEstimator = pkgs.symlinkJoin {
    name = "token-estimator";
    paths = [
      (pkgs.writeScriptBin "token-estimator" ''
        #!${pkgs.python3}/bin/python3
        """
        Token estimation utilities
        Approximates token count for routing decisions
        """
        import sys
        import json

        CHARS_PER_TOKEN = 4
        CHARS_PER_TOKEN_CODE = 6

        def estimate_tokens(text: str, is_code: bool = False) -> int:
            if not text:
                return 0
            divisor = CHARS_PER_TOKEN_CODE if is_code else CHARS_PER_TOKEN
            return max(1, len(text) // divisor)

        def recommend_model(token_count: int) -> str:
            if token_count <= 4096:
                return "qwen3.5-2b"
            elif token_count <= 32768:
                return "qwen3.5-4b"
            else:
                return "qwen3.5-35b-a3b@q4_k_m"

        if len(sys.argv) > 1:
            text = sys.argv[1]
            print(f"Estimated tokens: {estimate_tokens(text)}")
        else:
            data = json.load(sys.stdin)
            if "messages" in data:
                total = sum(estimate_tokens(msg.get("content", "")) for msg in data["messages"])
                print(json.dumps({
                    "estimated": total,
                    "recommended_model": recommend_model(total)
                }, indent=2))
      '')
    ];
  };


in {
  config = mkIf (cfg.enable && cfg.routing.enable) {
    # Add routing utilities to system packages
    environment.systemPackages = [ tokenEstimator ];

    # The routing logic is embedded in the gateway
    # This module primarily provides configuration and utilities
  };
}
