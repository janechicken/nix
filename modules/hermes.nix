{ config, pkgs, inputs, lib, ... }:

let
  cfg = config.programs.hermes-agent;
  hermesPackage = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
  hermesMessaging = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
in
{
  options.programs.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent - AI agent framework by Nous Research";

    package = lib.mkOption {
      type = lib.types.package;
      default = if cfg.enableMessaging then hermesMessaging else hermesPackage;
      defaultText = "hermes-agent (CLI) or hermes-agent-messaging (with gateway deps)";
      description = "Hermes Agent package to use.";
    };

    enableMessaging = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the messaging variant (includes Discord, Telegram, Slack dependencies).";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Attrs merged into ~/.hermes/config.yaml as YAML.";
      example = {
        model = {
          default = "deepseek-v4-flash";
          provider = "opencode-go";
        };
        agent = {
          max_turns = 90;
        };
      };
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = "Skill directories to symlink into ~/.hermes/skills/.";
      example = {
        ctf-solve = ./skills/ctf-solve;
      };
    };

    documents = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Documents written to ~/.hermes/ (AGENTS.md, SOUL.md, USER.md).";
      example.AGENTS.md = "You are on NixOS. Use nix-shell -p for missing tools.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Env vars written to ~/.hermes/.env (API keys, etc.).";
    };

    gateway = {
      enable = lib.mkEnableOption "Hermes gateway systemd user service";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.file = lib.mkMerge [
      # ~/.hermes/config.yaml
      {
        ".hermes/config.yaml" = {
          text = builtins.toJSON cfg.settings;
          force = true;
        };
      }

      # ~/.hermes/.env
      (lib.mkIf (cfg.environment != {}) {
        ".hermes/.env".text = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: "${k}=${v}") cfg.environment
        );
      })

      # ~/.hermes/skills/<name> → symlinks to skill dirs
      (builtins.listToAttrs (map (name: {
        name = ".hermes/skills/${name}";
        value = {
          source = cfg.skills.${name};
          force = true;
        };
      }) (builtins.attrNames cfg.skills)))

      # ~/.hermes/<documents> (AGENTS.md, SOUL.md, etc.)
      (builtins.listToAttrs (map (name: {
        name = ".hermes/${name}";
        value = {
          text = cfg.documents.${name};
          force = true;
        };
      }) (builtins.attrNames cfg.documents)))
    ];

    # Gateway systemd user service
    systemd.user.services.hermes-gateway = lib.mkIf cfg.gateway.enable {
      Unit = {
        Description = "Hermes Agent Gateway";
        After = [ "network.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/hermes gateway run";
        Restart = "on-failure";
        RestartSec = 10;
        Environment = [ "HERMES_HOME=%h/.hermes" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
