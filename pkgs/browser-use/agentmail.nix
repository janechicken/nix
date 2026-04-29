{ buildPythonPackage, fetchPypi, lib, httpx, pydantic, pydantic-core, typing-extensions, websockets, poetry-core }:

buildPythonPackage rec {
  pname = "agentmail";
  version = "0.0.59";
  format = "pyproject";
  src = fetchPypi {
    pname = "agentmail";
    inherit version;
    sha256 = "30549f014945d2c4987faac56817c9e17c5815305a04f71cc8518c42ef913ec7";
  };
  nativeBuildInputs = [ poetry-core ];
  propagatedBuildInputs = [ httpx pydantic pydantic-core typing-extensions websockets ];
  doCheck = false;
  pythonImportsCheck = [ "agentmail" ];
  meta = with lib; {
    description = "Temporary email service for AI agents";
    homepage = "https://github.com/browser-use/agentmail";
    license = licenses.mit;
  };
}
