{ buildPythonPackage, fetchPypi, lib, setuptools }:

buildPythonPackage rec {
  pname = "uuid7";
  version = "0.1.0";
  format = "setuptools";
  src = fetchPypi {
    inherit pname version;
    sha256 = "8c57aa32ee7456d3cc68c95c4530bc571646defac01895cfc73545449894a63c";
  };
  nativeBuildInputs = [ setuptools ];
  doCheck = false;
  pythonImportsCheck = [ "uuid_extensions" ];
  meta = with lib; {
    description = "UUID version 7, generating time-sorted UUIDs";
    homepage = "https://github.com/stevefan1999-personal/uuid7";
    license = licenses.mit;
  };
}
