{ config, pkgs, inputs, lib, ... }:

let
  yamlFormat = pkgs.formats.yaml { };
  hermesPackageBase = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Extra Python packages so check_tts_requirements() succeeds without
  # spawning pip subprocesses (saves ~4s on every startup).
  extraPythonEnv = pkgs.python312.withPackages (ps: with ps; [
    edge-tts
    elevenlabs
    mistralai
  ]);

  # sitecustomize.py to relax version pins in LAZY_DEPS on startup
  # (nixpkgs versions differ from upstream pinned == versions, which
  # would still trigger subprocess pip install attempts).
  lazyDepsPatch = pkgs.runCommand "lazy-deps-patch" {} ''
    mkdir -p $out/lib/python3.12/site-packages
    cat > $out/lib/python3.12/site-packages/sitecustomize.py << 'PYEOF'
import sys
import os

# sitecustomize runs before all site-packages are on sys.path (PEP 432).
# Resolve the Hermes env path from sys.executable so tools is importable.
_python_dir = os.path.dirname(sys.executable) if sys.executable else ""
_hermes_site = os.path.join(
    os.path.dirname(_python_dir), "lib", "python3.12", "site-packages"
)
if os.path.isdir(_hermes_site) and _hermes_site not in sys.path:
    sys.path.append(_hermes_site)

import tools.lazy_deps as _ld
_ld.LAZY_DEPS["tts.edge"] = ("edge-tts>=7.2.7",)
_ld.LAZY_DEPS["tts.elevenlabs"] = ("elevenlabs>=1.59.0",)
_ld.LAZY_DEPS["tts.mistral"] = ("mistralai>=2.4.0",)
PYEOF
  '';

  hermesPackage = hermesPackageBase.overrideAttrs (old: {
    buildInputs = (old.buildInputs or []) ++ [ extraPythonEnv lazyDepsPatch ];
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram $out/bin/hermes \
        --prefix PYTHONPATH : "${lazyDepsPatch}/${pkgs.python312.sitePackages}" \
        --prefix PYTHONPATH : "${extraPythonEnv}/${pkgs.python312.sitePackages}"
      wrapProgram $out/bin/hermes-agent \
        --prefix PYTHONPATH : "${lazyDepsPatch}/${pkgs.python312.sitePackages}" \
        --prefix PYTHONPATH : "${extraPythonEnv}/${pkgs.python312.sitePackages}"

      # Also patch the inner wrapper (.hermes-wrapped) to set PYTHONPATH
      # before its own exec, ensuring it reaches the Python process.
      _pypath="${lazyDepsPatch}/${pkgs.python312.sitePackages}:${extraPythonEnv}/${pkgs.python312.sitePackages}"
      for inner in "$out/bin/.hermes-wrapped" "$out/bin/.hermes-agent-wrapped"; do
        [ -f "$inner" ] || continue
        sed -i 's|^exec ".*$|PYTHONPATH="'"$_pypath"':$PYTHONPATH" ; export PYTHONPATH ; &|' "$inner"
      done
    '';
  });
  # hermesPackage = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
in {
  home.packages = [ hermesPackage ];

  home.file.".hermes/config.yaml" = {
    source = yamlFormat.generate "hermes-config" {
      model = {
        default = "deepseek-v4-flash";
        provider = "opencode-go";
      };

      agent = {
        max_turns = 90;
      };

      delegation = {
        model = "deepseek-v4-flash";
        provider = "opencode-go";
      };

      auxiliary = {
        vision = {
          provider = "opencode-go";
          model = "kimi-k2.6";
        };
      };

      gateway = {
        disable_slash_help_hint = true;
      };
    };
    force = true;
  };

  home.file.".hermes/AGENTS.md".text = ''
    You run on NixOS. If a tool/package is missing, use `nix-shell -p <pkg>` — never apt/pip/npm.
    Don't touch `nh os switch`/`nh home switch`, build-only.
  '';

  # systemd.user.services.hermes-gateway = {
  #   Unit = {
  #     Description = "Hermes Agent Gateway";
  #     After = [ "network.target" ];
  #   };
  #   Service = {
  #     Type = "simple";
  #     ExecStart = "${hermesPackage}/bin/hermes gateway run";
  #     Restart = "on-failure";
  #     RestartSec = 10;
  #     Environment = [ "HERMES_HOME=%h/.hermes" ];
  #   };
  #   Install = {
  #     WantedBy = [ "default.target" ];
  #   };
  # };
}
