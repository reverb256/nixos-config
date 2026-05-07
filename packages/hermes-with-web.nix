# Hermes Agent with web dashboard frontend + fastapi/uvicorn injected
#
# Creates a Python overlay that merges the hermes-agent venv with:
# 1. The built web_dist SPA frontend
# 2. fastapi + uvicorn + deps (optional [web] extras needed by `hermes dashboard`)
#
# Wheels are fetched via fetchurl (FOD) so they work in the Nix sandbox.
{
  pkgs,
  hermes-pkg,
  web-dist,
}: let
  # The hermes package wraps a venv. Find it from the binary.
  hermesVenv = pkgs.runCommand "hermes-venv-path" {} ''
    VENV_PATH=$(cat ${hermes-pkg}/bin/hermes | grep -oP '/nix/store/[a-z0-9]+-hermes-agent-env' | head -1)
    if [ -z "$VENV_PATH" ]; then
      echo "ERROR: Could not find hermes-agent-env in wrapper" >&2
      exit 1
    fi
    echo -n "$VENV_PATH" > $out
  '';

  # Pure-Python wheels fetched as FODs (no sandbox network issue)
  wheels = {
    fastapi = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/5c/05/5cbb59154b093548acd0f4c7c474a118eda06da25aa75c616b72d8fcd92a/fastapi-0.128.0-py3-none-any.whl";
      hash = "sha256-rr2T+XFu47T0/P4T/7fPMI2ZyfOrViLYh3RBByVhWC0=";
    };
    uvicorn = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/3d/d8/2083a1daa7439a66f3a48589a57d576aa117726762618f6bb09fe3798796/uvicorn-0.40.0-py3-none-any.whl";
      hash = "sha256-xsj1W8i/E+tvqf+HrWIwi7vDPQtn+EKTFR7+h+DV8u4=";
    };
    starlette = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/f7/1f/b876b1f83aef204198a42dc101613fefccb32258e5428b5f9259677864b4/starlette-0.47.2-py3-none-any.whl";
      hash = "sha256-xYR+lhNOXFNx7p+sb98aZzNtWBXgnrKgH9tXo1HvkVs=";
    };
    anyio = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/6f/12/e5e0282d673bb9746bacfb6e2dba8719989d3660cdb2ea79aee9a9651afb/anyio-4.10.0-py3-none-any.whl";
      hash = "sha256-YOR0rIZza7/W8hD3phIYk5wxj0P5lySXOB8cXpMO09E=";
    };
    sniffio = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/e9/44/75a9c9421471a6c4805dbf2356f7c181a29c1879239abab1ea2cc8f38b40/sniffio-1.3.1-py3-none-any.whl";
      hash = "sha256-L22kGNHx4P3dhER49BaA55TmBRkVeRoDT/ZeXxAFJaI=";
    };
    idna = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/76/c6/c88e154df9c4e1a2a66ccf0005a88dfb2650c1dffb6f5ce603dfbd452ce3/idna-3.10-py3-none-any.whl";
      hash = "sha256-lG0ZWg0lnLumEWXojmWUHxbps26m3bl/AEUrrosSh9M=";
    };
    click = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/db/d3/9dcc0f5797f070ec8edf30fbadfb200e71d9db6b84d211e3b2085a7589a0/click-8.3.0-py3-none-any.whl";
      hash = "sha256-m58oUwLG4wZPQzDAXwW4GUWyo5VEJ5ND5ufF8nqbrdw=";
    };
    h11 = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/04/4b/29cac41a4d98d144bf5f6d33995617b185d14b22401f75ca86f384e87ff1/h11-0.16.0-py3-none-any.whl";
      hash = "sha256-Y8+LvnUi3jv2WTL9odnCdyBk/7Pa5i1Vky2lSzHLbIY=";
    };
  };
in
  pkgs.runCommand "hermes-agent-with-web-${hermes-pkg.version or "0.10.0"}" {
    nativeBuildInputs = [pkgs.makeWrapper pkgs.unzip];
    buildInputs = [hermes-pkg];
  } ''
    mkdir -p $out/bin

    VENV=$(<${hermesVenv})

    # Create our overlay site-packages directory
    SITEPKG=$(find "$VENV/lib" -maxdepth 2 -name site-packages -type d | head -1)
    OVERLAY="$out/lib/$(basename $(dirname "$SITEPKG"))/site-packages"
    mkdir -p "$OVERLAY"

    # Create a .pth file pointing to the original venv site-packages
    echo "$SITEPKG" > "$OVERLAY/00-hermes-venv.pth"

    # Create the hermes_cli/web_dist directory with our built frontend
    mkdir -p "$OVERLAY/hermes_cli/web_dist"
    cp -r ${web-dist}/* "$OVERLAY/hermes_cli/web_dist/"
    for f in $SITEPKG/hermes_cli/*; do
      name=$(basename "$f")
      if [ "$name" != "web_dist" ] && [ ! -e "$OVERLAY/hermes_cli/$name" ]; then
        ln -s "$f" "$OVERLAY/hermes_cli/$name"
      fi
    done

    # Install fastapi+uvicorn wheels into overlay
    ${pkgs.unzip}/bin/unzip -qo ${wheels.fastapi} -d "$OVERLAY"
    ${pkgs.unzip}/bin/unzip -qo ${wheels.uvicorn} -d "$OVERLAY"
    ${pkgs.unzip}/bin/unzip -qo ${wheels.starlette} -d "$OVERLAY"
    ${pkgs.unzip}/bin/unzip -qo ${wheels.anyio} -d "$OVERLAY"
    ${pkgs.unzip}/bin/unzip -qo ${wheels.sniffio} -d "$OVERLAY"
    ${pkgs.unzip}/bin/unzip -qo ${wheels.idna} -d "$OVERLAY"
    ${pkgs.unzip}/bin/unzip -qo ${wheels.click} -d "$OVERLAY"
    ${pkgs.unzip}/bin/unzip -qo ${wheels.h11} -d "$OVERLAY"

    # Wrap hermes binaries with our overlay in PYTHONPATH (takes precedence)
    for bin in ${hermes-pkg}/bin/*; do
      name=$(basename "$bin")
      makeWrapper "$bin" "$out/bin/$name" \
        --prefix PYTHONPATH : "$OVERLAY" \
        --set HERMES_HOME "/var/lib/hermes/.hermes"
    done

    # Copy share
    if [ -d ${hermes-pkg}/share ]; then
      cp -r ${hermes-pkg}/share $out/share
    fi
  ''
