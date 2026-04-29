{ buildPythonPackage, fetchPypi, lib, httpx, pydantic, pydantic-core, typing-extensions, poetry-core }:

buildPythonPackage rec {
  pname = "browser-use-sdk";
  version = "2.0.15";
  format = "pyproject";
  src = fetchPypi {
    pname = "browser_use_sdk";
    inherit version;
    sha256 = "0832ae0998736e6386457e6cf506e2820db0d626c4d9dbf0f567ea2b6c6888d3";
  };
  nativeBuildInputs = [ poetry-core ];
  propagatedBuildInputs = [ httpx pydantic pydantic-core typing-extensions ];
  doCheck = false;
  pythonImportsCheck = [ "browser_use_sdk" ];
  meta = with lib; {
    description = "Python SDK for the Browser Use cloud API";
    homepage = "https://github.com/browser-use/browser-use";
    license = licenses.mit;
  };
}
