# OpenClaw hasown dependency workaround overlay
# Merged from openclaw-fix-overlay.nix and openclaw-workaround-overlay.nix
# Fixes upstream bug: https://github.com/openclaw/nix-openclaw/issues/45
# The form-data@2.5.4 package requires 'hasown' but it's not in the pnpm lockfile

final: prev:
let
  # Create a minimal hasown package that provides the missing module
  hasownStub = final.stdenvNoCC.mkDerivation {
    pname = "hasown";
    version = "2.0.2-fix1";  # Version bump to force rebuild

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
    '';
  };
  
  # Helper function to patch wrapper
  patchWrapper = final.writeShellScriptBin "patch-openclaw-wrapper" ''
    WRAPPER="$1"
    HASOWN_PATH="$2"
    
    if [ ! -f "$WRAPPER" ]; then
      echo "Error: $WRAPPER not found"
      exit 1
    fi
    
    echo "Patching wrapper: $WRAPPER with HASOWN_PATH=$HASOWN_PATH"
    
    # Read first line (shebang)
    SHEBANG=$(head -1 "$WRAPPER")
    
    # Create patched wrapper
    {
      echo "$SHEBANG"
      echo "export HASOWN_PATH=\"$HASOWN_PATH\""
      echo "export NODE_PATH=\"$HASOWN_PATH:\$NODE_PATH\""
      echo ""
      # Skip original shebang and mode line, keep the rest
      tail -n +3 "$WRAPPER"
    } > "$WRAPPER.patched"
    
    mv "$WRAPPER.patched" "$WRAPPER"
    chmod +x "$WRAPPER"
    
    echo "Wrapper patched successfully"
  '';
in {
  # Override the openclaw-gateway package from the nix-openclaw overlay
  openclaw-gateway =
    if prev ? openclaw-gateway
    then prev.openclaw-gateway.overrideAttrs (oldAttrs: {
      # Add hasown and patch script as build inputs
      nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ hasownStub patchWrapper ];

      # After the build, copy hasown into the node_modules
      postInstall = (oldAttrs.postInstall or "") + ''
        set -e

        echo "Applying hasown workaround for OpenClaw..."

        HASOWN_PATH="${hasownStub}/lib/node_modules"
        echo "HASOWN_PATH=$HASOWN_PATH"

        # Find the openclaw wrapper script
        OPENCLAW_BIN="$out/bin/openclaw"
        
        if [ -f "$OPENCLAW_BIN" ]; then
          echo "Found openclaw wrapper at: $OPENCLAW_BIN"
          
          # Copy hasown to all locations
          for DIR in \
            "$out/lib/openclaw/node_modules" \
            "$out/lib/openclaw/node_modules/.pnpm/node_modules" \
            "$out/lib/openclaw/node_modules/.pnpm"; do
            if [ -d "$DIR" ]; then
              echo "Copying hasown to: $DIR"
              cp -r "$HASOWN_PATH/hasown" "$DIR/" 2>/dev/null || true
            fi
          done
          
          # Copy to form-data's node_modules
          FORM_DATA_DIR=$(find "$out" -type d -name "form-data@2.5.4" 2>/dev/null | head -1)
          if [ -n "$FORM_DATA_DIR" ]; then
            echo "Found form-data at: $FORM_DATA_DIR"
            FORM_DATA_NODE_MODULES="$FORM_DATA_DIR/node_modules"
            if [ -d "$FORM_DATA_NODE_MODULES" ]; then
              echo "Copying hasown to: $FORM_DATA_NODE_MODULES"
              cp -r "$HASOWN_PATH/hasown" "$FORM_DATA_NODE_MODULES/"
            fi
          fi
          
          # Patch the wrapper using the helper script
          echo "Patching wrapper..."
          ${patchWrapper}/bin/patch-openclaw-wrapper "$OPENCLAW_BIN" "$HASOWN_PATH"
          
          # Verify the patch
          echo "Verifying wrapper..."
          head -5 "$OPENCLAW_BIN"
        else
          echo "Warning: openclaw wrapper not found at $OPENCLAW_BIN"
          ls -la "$out/bin/" 2>/dev/null || true
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
