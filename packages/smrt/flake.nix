{
  description = "TP-Link Easy Smart Switch management tool (smrt)";

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
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python3;
      in
      {
        packages.default = python.pkgs.buildPythonPackage rec {
          pname = "smrt";
          version = "1.0.0";
          format = "setuptools";

          src = pkgs.fetchFromGitHub {
            owner = "pklaus";
            repo = "smrt";
            rev = "master";
            sha256 = "sha256-FV7U4f6phrGWZeQiS9BdJOH5o1NhEgqDvoWmY74hDMw=";
          };

          propagatedBuildInputs = with python.pkgs; [
            netifaces
          ];

          doCheck = false;

          meta = with pkgs.lib; {
            description = "Python package to control TP-Link Easy Smart switches";
            homepage = "https://github.com/pklaus/smrt";
            license = licenses.gpl3;
            maintainers = [ ];
            platforms = platforms.linux ++ platforms.darwin;
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            (python.withPackages (
              ps: with ps; [
                netifaces
              ]
            ))
          ];
        };

        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
        };
      }
    );
}
