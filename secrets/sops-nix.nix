{ config, lib, pkgs, ... }:

{
  # Sops-nix secret management
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets."openrouter_api_key" = {
    path = "/run/secrets/openrouter_api_key";
  };

  environment.sessionVariables = {
    OPENROUTER_API_KEY = "$(cat /run/secrets/openrouter_api_key)";
  };
}
