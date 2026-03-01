{ config, lib, inputs, pkgs, ... }:

{
  home.packages = [ pkgs.sops pkgs.age ];
  imports = [
    inputs.sops-nix.homeManagerModules.sops
  ];

  sops.secrets = {
    deepseek_api_key = {
      sopsFile = ./secrets.yaml;
      path = "${config.home.homeDirectory}/.config/zed/deepseek_api_key";
    };
  };

  home.sessionVariables = lib.mkIf (config.sops.secrets ? deepseek_api_key) {
    DEEPSEEK_API_KEY = "$(cat ${config.sops.secrets.deepseek_api_key.path})";
  };
}
