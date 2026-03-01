{ config, lib, pkgs, ... }:

{
  home.packages = [ pkgs.sops pkgs.age ];
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    secrets = {
      deepseek_api_key = {
        sopsFile = ./secrets.yaml;
        path = "${config.home.homeDirectory}/.config/zed/deepseek_api_key";
      };
      openrouter_api_key = {
        sopsFile = ./secrets.yaml;
        path = "${config.home.homeDirectory}/.config/zed/openrouter_api_key"
      }
    };
  };
}
