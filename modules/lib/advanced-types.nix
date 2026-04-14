{
  lib,
  ...
}: rec {
  /*
  Create a type that accepts either a direct value or a path to a file containing that value
  Useful for API keys, tokens, passwords, etc.

  apiKeyType = lib.types.either lib.types.str lib.types.path;
  */
  eitherStrOrPath = lib.types.either lib.types.str lib.types.path;

  /*
  Create a type that accepts either an int (port number) or string (service name)
  Useful for network service configurations

  portOrServiceType = lib.types.either lib.types.int lib.types.str;
  */
  portOrService = lib.types.either lib.types.int lib.types.str;

  /*
  Create a type that accepts a URL (string) or a local Unix socket path
  Common for database and service connections

  urlOrSocketType = lib.types.oneOf [
    (lib.types.str // {description = "URL (e.g., https://example.com or postgres://localhost/db)";})
    (lib.types.path // {description = "Unix socket path (e.g., /run/service.sock)";})
  ];
  */
  urlOrSocket = lib.types.oneOf [
    (lib.types.str // {description = "URL (e.g., https://example.com or postgres://localhost/db)";})
    (lib.types.path // {description = "Unix socket path (e.g., /run/service.sock)";})
  ];

  /*
  Create a type for absolute paths (must start with /)
  Uses mkOptionType for custom validation

  absolutePath = absolutePathType;
  */
  absolutePathType = lib.mkOptionType {
    name = "absolute-path";
    description = "Absolute file path (must start with /)";
    check = path: builtins.substring 0 1 path == "/";
    merge = loc: defs:
      if defs == []
      then {throw "Cannot merge empty list of absolute paths";}
      else if builtins.length defs == 1
      then defs.head.value
      else defs.last.value;
  };

  /*
  Create a type for valid port numbers (1-65535)
  Uses mkOptionType for custom validation

  validPort = portType;
  */
  portType = lib.mkOptionType {
    name = "port";
    description = "TCP/UDP port number (1-65535)";
    check = port: port >= 1 && port <= 65535;
    merge = loc: defs:
      if defs == []
      then {throw "Cannot merge empty list of ports";}
      else if builtins.length defs == 1
      then defs.head.value
      else defs.last.value;
  };

  /*
  Create a type for non-empty strings
  Uses mkOptionType for custom validation

  nonEmptyStr = nonEmptyStringType;
  */
  nonEmptyStringType = lib.mkOptionType {
    name = "non-empty-string";
    description = "Non-empty string";
    check = str: builtins.stringLength str > 0 && builtins.stringLength (lib.strings.trim str) > 0;
    merge = loc: defs:
      if defs == []
      then {throw "Cannot merge empty list of strings";}
      else if builtins.length defs == 1
      then defs.head.value
      else defs.last.value;
  };

  /*
  Create a type for email addresses
  Basic validation using string matching

  email = emailType;
  */
  emailType = lib.mkOptionType {
    name = "email";
    description = "Email address";
    check = email:
      builtins.match "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" email != null;
    merge = loc: defs:
      if defs == []
      then {throw "Cannot merge empty list of emails";}
      else if builtins.length defs == 1
      then defs.head.value
      else defs.last.value;
  };
}
