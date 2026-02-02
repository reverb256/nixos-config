# OpenClaw hasown dependency workaround overlay
# Fixes upstream bug: https://github.com/openclaw/nix-openclaw/issues/45
# The form-data@2.5.4 package requires 'hasown' but it's not in the pnpm lockfile

final: prev:
let
  # Create a minimal hasown package that provides the missing module
  hasownStub = final.stdenvNoCC.mkDerivation {
    pname = "hasown";
    version = "2.0.2";

    # Minimal implementation of hasown - just provides the function that form-data needs
    buildCommand = ''
      mkdir -p $out/lib/node_modules/hasown

      # Create package.json
      cat > $out/lib/node_modules/hasown/package.json << 'EOF'
      {
        "name": "hasown",
        "version": "2.0.2",
        "main": "index.js",
        "description": "A stub implementation of hasown for OpenClaw workaround"
      }
      EOF

      # Create the main module that exports a simple hasOwnProperty wrapper
      cat > $out/lib/node_modules/hasown/index.js << 'EOF'
      'use strict';
      module.exports = function hasOwn(obj, prop) {
        return Object.prototype.hasOwnProperty.call(obj, prop);
      };
      EOF

      # Also create it at root level for convenience
      mkdir -p $out/lib
      ln -s $out/lib/node_modules/hasown $out/lib/hasown
    '';
  };
in {
  # Override the openclaw-gateway package from the nix-openclaw overlay
  openclaw-gateway =
    if prev ? openclaw-gateway
    then prev.openclaw-gateway.overrideAttrs (oldAttrs: {
      # Add hasown as a build input
      nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ hasownStub ];

      # After the build, copy hasown into the node_modules
      postInstall = (oldAttrs.postInstall or "") + ''
        set -e

        echo "Applying hasown workaround for OpenClaw..."

        HASOWN_PATH="${hasownStub}/lib/node_modules"
        echo "HASOWN_PATH=$HASOWN_PATH"

        # Copy hasown to all locations where form-data might look for it
        for DIR in \
          "$out/lib/openclaw/node_modules" \
          "$out/lib/openclaw/node_modules/.pnpm/node_modules"; do
          if [ -d "$DIR" ]; then
            echo "Copying hasown to: $DIR"
            cp -r "$HASOWN_PATH/hasown" "$DIR/" 2>/dev/null || true
          fi
        done

        # Also add to the form-data's parent node_modules
        FORM_DATA_DIR=$(find "$out" -type d -name "form-data@2.5.4" 2>/dev/null | head -1)
        if [ -n "$FORM_DATA_DIR" ]; then
          echo "Found form-data at: $FORM_DATA_DIR"
          PARENT_DIR="$(dirname "$FORM_DATA_DIR")/../node_modules"
          if [ -d "$PARENT_DIR" ]; then
            echo "Copying hasown to: $PARENT_DIR"
            cp -r "$HASOWN_PATH/hasown" "$PARENT_DIR/" 2>/dev/null || true
          fi
        fi

        # Patch the openclaw wrapper to add NODE_PATH
        if [ -f "$out/bin/openclaw" ]; then
          echo "Patching openclaw wrapper with NODE_PATH..."

          # Get the bash shebang from the original file
          SHEBANG=$(head -1 "$out/bin/openclaw")

          # Create a temporary file with the patched content
          # Note: Use $$ for literal $ in Nix strings
          {
            echo "$SHEBANG"
            echo "export HASOWN_PATH=""$HASOWN_PATH"""
            echo "export NODE_PATH=""$HASOWN_PATH:""$${NODE_PATH:-}"""
            echo ""
            # Skip first 2 lines of original (shebang and mode line)
            tail -n +3 "$out/bin/openclaw"
          } > "$out/bin/openclaw.tmp"

          mv "$out/bin/openclaw.tmp" "$out/bin/openclaw"
          chmod +x "$out/bin/openclaw"

          echo "Wrapper patched successfully"
        fi

        echo "hasown workaround applied successfully"
      '';
    })
    else prev.openclaw-gateway or null;

  # Override openclaw-tools if it exists
  openclaw-tools =
    if prev ? openclaw-tools
    then prev.openclaw-tools.overrideAttrs (oldAttrs: {
      nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ hasownStub ];
      postInstall = (oldAttrs.postInstall or "") + ''
        set -e
        HASOWN_PATH="${hasownStub}/lib/node_modules"
        # Copy hasown to node_modules
        if [ -d "$out/lib/node_modules" ]; then
          cp -r "$HASOWN_PATH/hasown" "$out/lib/node_modules/" 2>/dev/null || true
        fi
      '';
    })
    else prev.openclaw-tools or null;
}
