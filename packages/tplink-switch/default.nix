{ lib
, python3
, buildPythonPackage
,
}:
buildPythonPackage rec {
  pname = "tplink-switch";
  version = "0.1.0";
  format = "pyproject";

  src = ./.;

  propagatedBuildInputs = with python3.pkgs; [
    requests
    urllib3
  ];

  pythonImportsCheck = [ "tplink_switch" ];

  meta = with lib; {
    description = "Python library for managing TP-Link Easy Smart Switches via HTTP";
    homepage = "https://github.com/nixos-config/tplink-switch";
    license = licenses.mit;
    maintainers = [ "j_kro" ];
  };
}
