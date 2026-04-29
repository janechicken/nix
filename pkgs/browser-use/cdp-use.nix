{ buildPythonPackage, fetchPypi, lib, httpx, typing-extensions, websockets, hatchling }:

buildPythonPackage rec {
  pname = "cdp-use";
  version = "1.4.5";
  format = "pyproject";
  src = fetchPypi {
    pname = "cdp_use";
    inherit version;
    sha256 = "0da3a32df46336a03ff5a22bc6bc442cd7d2f2d50a118fd4856f29d37f6d26a0";
  };
  nativeBuildInputs = [ hatchling ];
  propagatedBuildInputs = [ httpx typing-extensions websockets ];
  doCheck = false;
  pythonImportsCheck = [ "cdp_use" ];
  meta = with lib; {
    description = "Type safe generator/client library for CDP";
    homepage = "https://github.com/browser-use/cdp-use";
    license = licenses.mit;
  };
}
