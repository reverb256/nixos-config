{ stdenv, writeShellScriptBin }:
writeShellScriptBin "lolMiner" ''
  echo "lolMiner is no longer available. Use peakminer instead." >&2
  exit 1
''
