{ config, lib, pkgs, ... }:

{
  home.packages = [ pkgs.sops pkgs.age ];
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    secrets = {
      openrouter_api_key = {
        sopsFile = ./secrets.yaml;
        path = "${config.home.homeDirectory}/.config/zed/openrouter_api_key";
      };
    };
  };
}
