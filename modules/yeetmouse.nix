{ lib, config, ... }:

with lib;
let
  cfg = config.modules.desktop;
in {
  options.modules.desktop.rawaccel = {
    enable = mkOption {
      default = true;
      example = true;
      description = "Whether to enable Yeetmouse (fork of Leetmouse / Rawaccel for Linux).";
      type = types.bool;
    };
  };

  config = mkIf cfg.rawaccel.enable {
    hardware.yeetmouse = {
      enable = true;
      sensitivity = 0.25;
      offset = 5.0;
      # inputCap = 35.0;
      OutputCap = 20.0;
    };
  };
}
