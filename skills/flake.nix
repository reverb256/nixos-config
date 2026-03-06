{
  description = "NixOS MCP servers for Claude Code skills";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    flake-utils.lib.eachSystem [ system ] (
      system:
      let
        inherit pkgs system;
      in
      {
        packages.${system} = {
          # NixOS Skills MCP Server Package
          nixos-skills-mcp = pkgs.python312Packages.buildPythonPackage rec {
            pname = "nixos-skills-mcp";
            version = "1.0.0";
            src = self;

            # Runtime dependencies
            propagatedBuildInputs = with pkgs.python312Packages; [
              # MCP SDK will be added once available in nixpkgs
              # For now, we'll use a minimal implementation
            ];

            # MCP servers
            sources = {
              "nix-rebuild" = ./nix-rebuild-mcp/server.py;
              "add-service" = ./add-service-mcp/server.py;
            };
          };
        };
      }
    );
}
