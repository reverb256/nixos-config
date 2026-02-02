# OpenClaw hasown dependency workaround overlay
# Fixes upstream bug: https://github.com/openclaw/nix-openclaw/issues/45
# The form-data@2.5.4 package requires 'hasown' but it's not in the pnpm lockfile

final: prev: let
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
      
      # Symlink for convenience
      mkdir -p $out/lib
      ln -s $out/lib/node_modules/hasown $out/lib/hasown
    '';
  };
  
  # Function to patch an OpenClaw package
  patchOpenclawPkg = pkg: 
    if pkg == null then null else
    pkg.overrideAttrs (oldAttrs: {
      # Add hasown as a build input
      nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ 
        final.makeWrapper
        hasownStub 
      ];
      
      # After the build, copy hasown into the node_modules
      postInstall = (oldAttrs.postInstall or "") + ''
        echo "Applying hasown workaround for OpenClaw..."
        
        # Find all form-data directories and add hasown to their parent node_modules
        for FORM_DATA_DIR in $(find $out -type d -name "form-data@2.5.4" 2>/dev/null); do
          echo "Found form-data at: $FORM_DATA_DIR"
          PARENT_NODE_MODULES="$(dirname "$FORM_DATA_DIR")/../node_modules"
          if [ -d "$PARENT_NODE_MODULES" ]; then
            echo "Copying hasown to: $PARENT_NODE_MODULES"
            cp -r ${hasownStub}/lib/node_modules/hasown "$PARENT_NODE_MODULES/"
          fi
        done
        
        # Also add to the main node_modules/.pnpm/node_modules if it exists
        if [ -d "$out/lib/openclaw/node_modules/.pnpm/node_modules" ]; then
          echo "Copying hasown to pnpm node_modules"
          cp -r ${hasownStub}/lib/node_modules/hasown "$out/lib/openclaw/node_modules/.pnpm/node_modules/"
        fi
        
        # Create a wrapper script that sets NODE_PATH to include hasown
        if [ -f "$out/bin/openclaw" ]; then
          echo "Wrapping openclaw binary with hasown in NODE_PATH"
          wrapProgram "$out/bin/openclaw" \
            --prefix NODE_PATH : "${hasownStub}/lib/node_modules"
        fi
        
        echo "hasown workaround applied successfully"
      '';
    });
in {
  # Override the openclaw-gateway package from the nix-openclaw overlay
  # The nix-openclaw overlay should have already added this to prev
  openclaw-gateway = 
    if prev ? openclaw-gateway 
    then patchOpenclawPkg prev.openclaw-gateway
    else prev.openclaw-gateway or null;
  
  # Override openclaw-tools if it exists
  openclaw-tools = 
    if prev ? openclaw-tools 
    then patchOpenclawPkg prev.openclaw-tools
    else prev.openclaw-tools or null;
}
