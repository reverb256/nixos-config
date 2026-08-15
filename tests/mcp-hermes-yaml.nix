# Regression test for issue #638: the Hermes mcp_servers YAML generator used
# to emit broken YAML that failed hermes-mcp-servers.service on every host:
#   1. The addLine closure re-emitted the "    <name>:" key once per field,
#      producing duplicate keys (ruamel DuplicateKeyError).
#   2. Unquoted description/arg/command values containing ": " (colon-space)
#      produced invalid YAML (ruamel.yaml.ScannerError "mapping values are
#      not allowed here").
#   3. The mcp_servers: header sat level with the server keys (a null
#      sibling) instead of being their parent mapping.
#
# The generator was rewritten (modules/services/mcp-server-registry.nix,
# merged 2026-08-15 as 7e6667e4a, and issue #638 deltas on top). This test
# evaluates the real registry module and asserts — at eval time, per the
# repo's check convention — that every risky field is a double-quoted
# scalar, that every registered server appears exactly once as a nested key,
# and that mcp_servers: is the 2-space-indented parent mapping.
{pkgs}: let
  inherit (pkgs) lib;
  module = import ../modules/services/mcp-server-registry.nix;
  result = (import (pkgs.path + "/nixos/lib/eval-config.nix")) {
    inherit (pkgs) system;
    modules = [
      module
      {services.mcp-registry.enable = true;}
    ];
  };
  yaml = result.config.lib.mcp-registry.hermesMcpYamlText;
  lines = lib.strings.splitString "\n" yaml;

  # url values (e.g. "http://kubernetes-mcp.infra...:8080/mcp") are emitted
  # as plain scalars (no ": " inside them); only description/command/args are
  # required to be double-quoted.
  quotedFields = ["description" "command"];

  isFieldLine = f: line: lib.strings.hasPrefix "${f}: " (lib.strings.trim line);
  isQuotedFieldLine = f: line: lib.strings.hasPrefix "${f}: \"" (lib.strings.trim line);
  isArgLine = line: lib.strings.hasPrefix "- " (lib.strings.trim line);

  # Every field assignment must emit a double-quoted scalar value.
  unquotedFieldLines = builtins.concatLists (
    map (f: builtins.filter (line: isFieldLine f line && !(isQuotedFieldLine f line)) lines) quotedFields
  );

  # Every args entry must be a double-quoted scalar value.
  unquotedArgLines = builtins.filter (line: isArgLine line && !(lib.strings.hasPrefix "- \"" (lib.strings.trim line))) lines;

  # Every registered server must appear exactly once as a 4-space-nested key.
  serverNames = builtins.attrNames result.config.lib.mcp-registry.allServers;
  badServerKeys = builtins.filter (name: (builtins.length (builtins.filter (line: line == "    ${name}:") lines)) != 1) serverNames;

  # The mcp_servers: header must be the 2-space-indented parent mapping.
  hasNestedMcpServers = lib.any (line: line == "  mcp_servers:") lines;

  failures =
    map (l: "unquoted scalar on line: ${l}") unquotedFieldLines
    ++ map (l: "unquoted arg on line: ${l}") unquotedArgLines
    ++ map (n: "server key must appear exactly once: ${n}") badServerKeys
    ++ lib.optional (!hasNestedMcpServers) "missing parent '  mcp_servers:' mapping (server keys must be nested under it)";

  passed = failures == [];
in
  assert passed
  || (builtins.trace "\n=== mcp-hermes-yaml test FAILED ===\n${builtins.toJSON failures}" (
    throw "mcp-hermes-yaml test failed: ${builtins.toJSON failures}"
  )); {inherit passed failures;}
