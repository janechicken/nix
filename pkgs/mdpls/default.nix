{ lib, rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "mdpls";
  version = "0.1.0-unstable-2026-05-15";

  src = fetchFromGitHub {
    owner = "euclio";
    repo = "mdpls";
    rev = "329a63d045497a7af3371eefd828424a67ca5d61";
    hash = "sha256-FIPEkuPUJJlhBG8jGKXctJp+HpymzKOF91RXBCSsKPE=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  meta = with lib; {
    description = "Markdown Preview Language Server — live HTML preview with math (KaTeX) support";
    homepage = "https://github.com/euclio/mdpls";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
