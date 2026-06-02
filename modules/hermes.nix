{ config, pkgs, inputs, lib, ... }:

let
  yamlFormat = pkgs.formats.yaml { };
  hermesPackage = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
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

      gateway = {
        disable_slash_help_hint = true;
      };
    };
    force = true;
  };

  home.file.".hermes/AGENTS.md".text = ''
    You run on NixOS. If a tool/package is missing, use `nix-shell -p <pkg>` — never apt/pip/npm.
    Config lives in `~/src/nix/` — modules are one file per concern.
    Don't touch `nh os switch`/`nh home switch`, build-only.
  '';

  systemd.user.services.hermes-gateway = {
    Unit = {
      Description = "Hermes Agent Gateway";
      After = [ "network.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${hermesPackage}/bin/hermes gateway run";
      Restart = "on-failure";
      RestartSec = 10;
      Environment = [ "HERMES_HOME=%h/.hermes" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
