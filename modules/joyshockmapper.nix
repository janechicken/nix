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
    environment.sessionVariables = {
      SDL_GAMEPADCONTROLLERCONFIG = "03000000c82d00001260000000000000,8BitDo Ultimate 2 Wireless,a:b0,b:b1,dpleft:h0.8,dpdown:h0.4,dpright:h0.2,dpup:h0.1,leftshoulder:b6,leftstick:b13,lefttrigger:b8,leftx:a0,lefty:a2,paddle1:b11,paddle2:b12,paddle3:b13,paddle4:b14,rightshoulder:b7,rightstick:b14,righttrigger:b9,rightx:a3,righty:a5,x:b3,y:b4,
05000000c82d00001260000000000000,8BitDo Ultimate 2 Wireless,a:b0,b:b1,dpleft:h0.8,dpdown:h0.4,dpright:h0.2,dpup:h0.1,leftshoulder:b6,leftstick:b13,lefttrigger:b8,leftx:a0,lefty:a2,paddle1:b11,paddle2:b12,paddle3:b13,paddle4:b14,rightshoulder:b7,rightstick:b14,righttrigger:b9,rightx:a3,righty:a5,x:b3,y:b4,";
    };
    environment.systemPackages = [ cfg.package ];
    services.udev.packages = [ cfg.package ];

    users.users.jane = mkIf cfg.addUserToInput {
      extraGroups = [ "input" ];
    };
  };
}
