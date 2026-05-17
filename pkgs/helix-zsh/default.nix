{ lib, fetchFromGitHub, fetchurl, git, rustPlatform }:

let
  pname = "helix-driver";
  version = "0.1.0-unstable-2026-05-16";

  helixRev = "d79cce4e4bfc24dd204f1b294c899ed73f7e9453";

  src = fetchFromGitHub {
    owner = "john-h-k";
    repo = "helix-zsh";
    rev = "main";
    hash = "sha256-ZbRUoKqaMfagOZFuj+csdcsV1oAOtf9s6XqRGtOcfmc=";
  };

  helixRootFiles = fetchurl {
    url = "https://github.com/helix-editor/helix/archive/${helixRev}.tar.gz";
    hash = "sha256-Cc0blT5sgEVw7N35zigJjFBTFiOkyuTpa27QwPJakPA=";
  };
in
rustPlatform.buildRustPackage {
  inherit pname version src;

  cargoRoot = "helix-driver";
  buildAndTestSubdir = "helix-driver";

  cargoHash = "sha256-fS4WEV02FisHKEi6WBeo9FqtCeaIeXjR9/PrDeCtTps=";

  HELIX_DISABLE_AUTO_GRAMMAR_BUILD = 1;

  nativeBuildInputs = [ git ];

  # Cargo vendor flattens git workspace deps into per-crate directories,
  # losing repo root files that helix crates include via include_bytes!.
  # Extract root files from helix source and copy into source-git-0 dir.
  postPatch = ''
    helix_root="$NIX_BUILD_TOP/helix-root"
    mkdir -p "$helix_root"
    tar -xzf ${helixRootFiles} -C "$helix_root" --strip-components=1
    find "$NIX_BUILD_TOP" -maxdepth 3 -name source-git-0 -type d 2>/dev/null | while read dir; do
      cp "$helix_root"/{languages.toml,theme.toml,base16_theme.toml} "$dir/"
    done
  '';

  postInstall = ''
    mkdir -p $out/share/helix-zsh
    cp $src/helix_zsh.zsh $out/share/helix-zsh/
  '';

  meta = with lib; {
    description = "Helix editor keybindings for zsh shell";
    homepage = "https://github.com/john-h-k/helix-zsh";
    license = licenses.mit;
    maintainers = [];
  };
}
