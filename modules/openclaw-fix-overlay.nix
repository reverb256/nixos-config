# OpenClaw hasown dependency workaround
# Creates a patched version of openclaw-gateway with hasown included
# Fixes upstream bug: https://github.com/openclaw/nix-openclaw/issues/45

final: prev:
let
  # Create hasown package
  hasown-pkg = final.stdenvNoCC.mkDerivation {
    pname = "hasown-fix";
    version = "2.0.2.fix";

    buildCommand = ''
      mkdir -p $out/lib/node_modules
      cat > $out/lib/node_modules/package.json << 'EOF'
{
  "name": "hasown",
  "version": "2.0.2",
  "main": "index.js"
}
EOF
      cat > $out/lib/node_modules/index.js << 'EOF'
module.exports = Object.hasOwn || function(obj, prop) {
  return Object.prototype.hasOwnProperty.call(obj, prop);
};
EOF
    '';
  };
in {
  # Override openclaw-gateway with patched version
  openclaw-gateway = 
    if prev ? openclaw-gateway 
    then prev.openclaw-gateway.overrideAttrs (oldAttrs: {
      postPatch = (oldAttrs.postPatch or "") + ''
        # Add hasown to node_modules
        HASOWN_PATH="${hasown-pkg}/lib/node_modules"
        
        # Create hasown directory in form-data's node_modules
        FORM_DATA_DIR="$out/lib/openclaw/node_modules/.pnpm/form-data@2.5.4/node_modules"
        mkdir -p "$FORM_DATA_DIR"
        ln -sf "$HASOWN_PATH" "$FORM_DATA_DIR/hasown" 2>/dev/null || true
        
        # Also add to root node_modules
        mkdir -p "$out/lib/openclaw/node_modules"
        ln -sf "$HASOWN_PATH" "$out/lib/openclaw/node_modules/hasown" 2>/dev/null || true
        
        echo "hasown workaround applied"
      '';

      # Wrap the binary to set NODE_PATH
      postInstall = (oldAttrs.postInstall or "") + ''
        WRAPPER="$out/bin/openclaw"
        if [ -f "$WRAPPER" ]; then
          # Add NODE_PATH export to the wrapper
          sed -i 's|^exec "|HASOWN_PATH="'"$out/lib/node_modules"'"\nexport NODE_PATH="$HASOWN_PATH:$NODE_PATH"\nexec "|' "$WRAPPER"
        fi
      '';
    })
    else prev.openclaw-gateway or null;
}
