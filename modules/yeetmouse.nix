{ config, inputs, pkgs, lib, ... }:

{
  hardware.yeetmouse = {
    enable = true;
    parameters = {
      Sensitivity = 0.25;
      OutputCap = 20.0;
      Offset = 5.0;
    };
  };
}
