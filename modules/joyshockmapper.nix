{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.joyshockmapper;
in
{
  options.services.joyshockmapper = {
    enable = mkEnableOption "JoyShockMapper — gyro-to-KB/M controller mapper";

    package = mkOption {
      type = types.package;
      default = pkgs.joyshockmapper;
      defaultText = literalExpression "pkgs.joyshockmapper";
      description = "JoyShockMapper package to use.";
    };

    addUserToInput = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Add the primary user to the input group for /dev/uinput and /dev/hidraw* access.
        JoyShockMapper needs this to capture controller input and synthesize keyboard/mouse events.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    services.udev.packages = [ cfg.package ];

    users.users.jane = mkIf cfg.addUserToInput {
      extraGroups = [ "input" ];
    };
  };
}
