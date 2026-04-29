{ buildPythonPackage, fetchPypi, lib, aiofiles, anyio, portalocker, pydantic, typing-extensions, uuid7, hatchling }:

buildPythonPackage rec {
  pname = "bubus";
  version = "1.5.6";
  format = "pyproject";
  src = fetchPypi {
    inherit pname version;
    sha256 = "1a5456f0a576e86613a7bd66e819891b677778320b6e291094e339b0d9df2e0d";
  };
  nativeBuildInputs = [ hatchling ];
  propagatedBuildInputs = [ aiofiles anyio portalocker pydantic typing-extensions uuid7 ];
  doCheck = false;
  pythonImportsCheck = [ "bubus" ];
  meta = with lib; {
    description = "Advanced Pydantic-powered event bus with async support";
    homepage = "https://github.com/glass-dev/bubus";
    license = licenses.mit;
  };
}
