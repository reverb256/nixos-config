{
  lib,
  python313,
}:
python313.pkgs.buildPythonApplication {
  pname = "nixos-cluster-mcp";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = with python313.pkgs; [setuptools];

  dependencies = with python313.pkgs; [mcp];

  meta = with lib; {
    description = "MCP server for NixOS cluster management";
    license = licenses.mit;
    mainProgram = "nixos-cluster-mcp";
  };
}
