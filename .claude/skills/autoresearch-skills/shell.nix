{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    python3
    python3Packages.openai
    python3Packages.streamlit
    python3Packages.pandas
    python3Packages.plotly
    python3Packages.python-dotenv
  ];

  shellHook = ''
    echo "🔬 Autoresearch Environment Loaded"
    echo ""
    echo "Available commands:"
    echo "  python3 autoresearch.py --once       # Run single cycle"
    echo "  python3 autoresearch.py --cycles 5   # Run N cycles"
    echo "  python3 autoresearch.py              # Run continuous loop"
    echo "  python3 dashboard.py                 # Start web dashboard"
    echo ""
    echo "Environment variables:"
    echo "  SKILL_NAME=nix-rebuild               # Skill to optimize"
    echo "  ZAI_API_KEY=read from /run/agenix   # Auto-loaded from agenix"
    echo "  CLAUDE_CODE_PATH=/etc/nixos          # Project path"
    echo ""
  '';
}
