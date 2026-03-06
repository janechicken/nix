{ config, lib, pkgs, ... }:

{
  # Sops-nix secret management
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets."openrouter_api_key" = {
    owner = config.users.users.jane.name;
  };
  sops.secrets."deepseek_api_key" = {
    owner = config.users.users.jane.name;
  };
  sops.secrets."ssh_key" = {
    owner = config.users.users.jane.name;
    path = "/home/jane/.ssh/id_rsa";
  };
  sops.secrets."ssh_pubkey" = {
    owner = config.users.users.jane.name;
    path = "/home/jane/.ssh/id_rsa.pub";
  };
  # sops.secrets."gpg_key" = { # uncomment when needed
  #   owner = config.users.users.jane.name;
  # };

  # Set environment variable system-wide
  environment.sessionVariables = {
    OPENROUTER_API_KEY = "$(cat /run/secrets/openrouter_api_key)";
    DEEPSEEK_API_KEY = "$(cat /run/secrets/deepseek_api_key)";
  };
}
