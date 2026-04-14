{
  lib,
  types,
  ...
}: rec {
  /*
  Create a boolean enable option (standard pattern)

  mkEnableOption "My service"
  */
  inherit (lib) mkEnableOption;

  /*
  Create a port option with type checking

  mkPortOption 8080
  */
  mkPortOption = default: {
    type = types.port;
    inherit default;
  };

  /*
  Create a string option with default value

  mkStringOption "default-value"
  */
  mkStringOption = default: {
    type = types.str;
    inherit default;
  };

  /*
  Create a path option with default value

  mkPathOption "/var/lib/my-service"
  */
  mkPathOption = default: {
    type = types.path;
    inherit default;
  };

  /*
  Create an optional string/path option (nullOr)

  mkOptionalStringOption
  mkOptionalPathOption
  */
  mkOptionalStringOption = {
    type = types.nullOr types.str;
    default = null;
  };

  mkOptionalPathOption = {
    type = types.nullOr types.path;
    default = null;
  };

  /*
  Create a list option with element type

  mkListOption types.str [ "item1" "item2" ]
  */
  mkListOption = elemType: default: {
    type = types.listOf elemType;
    inherit default;
  };

  /*
  Create a submodule option (for nested configurations)

  mkSubmoduleOption (submodule: {
    options.foo = mkOptionOption "bar";
  })
  */
  mkSubmoduleOption = submodule: {
    type = types.submodule submodule;
  };

  /*
  Create a package option

  mkPackageOption pkgs.hello
  */
  mkPackageOption = default: {
    type = types.package;
    inherit default;
  };

  /*
  Common port range definitions
  */
  portRanges = {
    ephemeral = {
      min = 32768;
      max = 60999;
    };

    service = {
      min = 1024;
      max = 49151;
    };
  };
}
