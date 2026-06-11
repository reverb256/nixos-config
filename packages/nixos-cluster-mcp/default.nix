{ lib, python313, pkgs }:
python313.pkgs.buildPythonApplication {
  pname = "nixos-cluster-mcp";
  version = "0.1.2";
  pyproject = true;

  src = ./.;

  build-system = with python313.pkgs; [ setuptools ];

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dependencies = with python313.pkgs; [ fastmcp ];

  postInstall = ''
    wrapProgram $out/bin/nixos-cluster-mcp \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.kubectl ]}
  '';

  meta = with lib; {
    description = "MCP server for NixOS cluster management";
    license = licenses.mit;
    mainProgram = "nixos-cluster-mcp";
  };
}
