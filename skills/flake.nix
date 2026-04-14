{
  description = "NixOS MCP servers for Claude Code skills";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in
    flake-utils.lib.eachSystem [system] (
      system: let
        inherit pkgs system;
      in {
        packages.${system} = {
          nixos-skills-mcp = pkgs.python312Packages.buildPythonPackage rec {
            pname = "nixos-skills-mcp";
            version = "1.0.0";
            src = self;
            propagatedBuildInputs = with pkgs.python312Packages; [
            ];
            sources = {
              "nix-rebuild" = ./nix-rebuild-mcp/server.py;
              "add-service" = ./add-service-mcp/server.py;
            };
          };
        };
      }
    );
}
