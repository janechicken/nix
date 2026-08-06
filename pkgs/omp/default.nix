{
  lib,
  stdenv,
  fetchurl,
  patchelf,
  glibc,
}:

let
  version = "17.2.9";
  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-x64";
    hash = "sha256-T3rrM7LzR8EaWsjHNjDjHQLAo+7zaTRoiAufXo8CoCs=";
  };
in
stdenv.mkDerivation {
  pname = "omp";
  inherit version src;

  dontUnpack = true;
  # Nix's default fixupPhase strips the binary. Stripping removes the embedded
  # Bun runtime's section/note data and the binary degrades to bare `bun --help`.
  dontStrip = true;

  nativeBuildInputs = [ patchelf ];
  buildInputs = [ glibc ];

  # The GitHub release asset is a Bun-compiled bundle that embeds its own
  # runtime image in the ELF. autoPatchelfHook rewrites more than the dynamic
  # linker pointer (it mangles the embedded runtime and the binary degrades to
  # a bare `bun --help`). Only the `.interp` needs to change so the process
  # loads through NixOS's glibc loader.
  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/omp
    patchelf --set-interpreter ${glibc}/lib/ld-linux-x86-64.so.2 $out/bin/omp
    runHook postInstall
  '';

  meta = {
    description = "oh-my-pi: coding agent with the IDE wired in (fork of pi)";
    homepage = "https://omp.sh";
    license = lib.licenses.asl20;
    mainProgram = "omp";
    platforms = [ "x86_64-linux" ];
  };
}
