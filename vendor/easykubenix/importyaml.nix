{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.importyaml;
  settingsFormat = pkgs.formats.json {};
  globalConfig = config;

  importyaml = types.submodule (
    {config, ...}: let
      yamlConfig = config;
    in {
      options = {
        src = mkOption {
          description = ''
            Should be either a derivation, a URL string, or an attrset passed
            to builtins.fetchTree. Under pure-eval (enabled cluster-wide),
            `builtins.fetchTree` without a hash is rejected, so a bare URL
            string is an error — supply the hash via the attrset form:
            `src = { url = "..."; hash = "<sri-hash>"; };` (or better, a
            pkgs.runCommand derivation).
          '';
          type = types.either types.package (types.either types.str types.attrs);
        };
        overrides = mkOption {
          description = "Overrides to apply to all chart objects, don't do namespace here";
          type = lib.types.listOf (types.functionTo settingsFormat.type);
          default = [];
        };
        convertLists = mkOption {
          description = ''
            Converts lists where all entires have a name attribute into
            attrsets instead. These attrsets are converted back into
            lists before rendering Kubernetes manifests.
          '';
          type = types.bool;
          default = true;
        };
        objects = mkOption {
          description = "Generated kubernetes objects";
          type = types.listOf types.attrs;
          default = [];
        };
      };
      config = {
        # list to attrset convertion is just a preconfigured override
        overrides = lib.optional yamlConfig.convertLists (
          lib.mkBefore (object: (lib.walkWithPath (lib.kubeListsToAttrs object)) object)
        );

        objects = let
          # Pure-eval guard (see the `src` option description): derivations are
          # already pure-safe; hashed attrset form passes straight through to
          # fetchTree; a bare URL string has no hash and would be rejected by
          # pure-eval with a confusing error — fail loudly here instead with
          # instructions.
          src =
            if isDerivation yamlConfig.src
            then yamlConfig.src
            else if isString yamlConfig.src
            then
              throw ''
                importyaml: URL source "${yamlConfig.src}" has no hash, and
                pure-eval (enabled cluster-wide) forbids hash-less fetches.
                Use `src = { url = "..."; hash = "<sri-hash>"; };` or a
                pkgs.runCommand derivation instead of a bare URL string.
              ''
            else if (yamlConfig.src ? hash) || (yamlConfig.src ? narHash)
            then
              builtins.fetchTree (yamlConfig.src // { type = "file"; })
            else
              throw ''
                importyaml: attrset source has no `hash`/`narHash`, and pure-eval
                (enabled cluster-wide) forbids hash-less fetches. Add
                `hash = "<sri-hash>";` (or `narHash`) to the src attrset.
              '';

          list = lib.importJSON (
            pkgs.runCommand "yaml2json" {} # bash
            
            ''
              ${pkgs.yq}/bin/yq -Scs '.' ${src} >$out
            ''
          );
        in
          list;
      };
    }
  );
in {
  options.importyaml = mkOption {
    type = types.attrsOf importyaml;
    default = {};
  };
  config = let
    allObjects = lib.pipe cfg [
      (lib.mapAttrsToList (
        _: importspec: lib.map (object: lib.pipe object importspec.overrides) importspec.objects
      ))
      lib.flatten
    ];
  in {
    kubernetes.objects = lib.pipe allObjects [
      (lib.map (object: {
        ${object.metadata.namespace or "none"}.${object.kind}.${object.metadata.name} = object;
      }))
      lib.mkMerge
    ];
    kubernetes.apiMappings = lib.pipe allObjects [
      (lib.filter (object: object.kind or null == "CustomResourceDefinition"))
      (map (crd: {
        name = crd.spec.names.kind;
        value = let
          version = lib.pipe crd.spec.versions [
            (lib.filter (x: x.storage or false == true))
            lib.head
            (x: x.name)
          ];
        in
          lib.mkDefault "${crd.spec.group}/${version}";
      }))
      lib.listToAttrs
    ];
  };
}
