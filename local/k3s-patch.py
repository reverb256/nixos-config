with open('/etc/nixos/modules/services/k3s-cluster.nix', 'r') as f:
    lines = f.readlines()

new_lines = [
    "      # Pin k3s to 1.34.5 — k3s 1.35.x has a broken re-exec loop that crashes\n",
    "      # even with wrappers. Override the package to fetch the 1.34.5 binary.\n",
    "      package = let\n",
    '        k3sBin = pkgs.fetchurl {\n',
    '          url = "https://github.com/k3s-io/k3s/releases/download/v1.34.5+k3s1/k3s";\n',
    '          hash = "sha256-kAlneujh3SoHuono4kFy0sLHyPH0ZTPXwzWTjObOUmk=";\n',
    "        };\n",
    '      in pkgs.runCommand "k3s-with-agent" {\n',
    "        nativeBuildInputs = [ pkgs.installShellFiles ];\n",
    "      } ''\n",
    "        mkdir -p $out/bin\n",
    "        cp ${k3sBin} $out/bin/.k3s-wrapped\n",
    "        chmod +x $out/bin/.k3s-wrapped\n",
    "        ln -s .k3s-wrapped $out/bin/k3s\n",
    "        ln -s .k3s-wrapped $out/bin/k3s-agent\n",
    "        ln -s .k3s-wrapped $out/bin/crictl\n",
    "        ln -s .k3s-wrapped $out/bin/ctr\n",
    "        ln -s .k3s-wrapped $out/bin/kubectl\n",
    "      '';\n",
]

result = lines[:121] + new_lines + lines[134:]

with open('/etc/nixos/modules/services/k3s-cluster.nix', 'w') as f:
    f.writelines(result)

print(f"OK: replaced lines 122-134 with {len(new_lines)} new lines")
