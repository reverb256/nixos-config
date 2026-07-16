{
  lib,
  python313,
}:
python313.pkgs.buildPythonApplication {
  pname = "buffy-mcp";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = with python313.pkgs; [setuptools];

  dependencies = with python313.pkgs; [
    fastmcp
    libtmux
    requests
  ];

  meta = with lib; {
    description = "Buffy — local port of Freebuff tool primitives (file picker, code search, bash, browser, docs). No cloud egress.";
    license = licenses.mit;
    mainProgram = "buffy-mcp";
  };
}
