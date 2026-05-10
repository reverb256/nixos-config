{
  lib,
  python313,
}:
python313.pkgs.buildPythonApplication {
  pname = "nixos-cluster-mcp";
  version = "0.1.1";
  pyproject = true;

  src = ./.;

  build-system = with python313.pkgs; [setuptools];

  dependencies = with python313.pkgs; [fastmcp];

  meta = with lib; {
    description = "MCP server for NixOS cluster management";
    license = licenses.mit;
    mainProgram = "nixos-cluster-mcp";
  };
}
