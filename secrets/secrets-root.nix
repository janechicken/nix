{ config, inputs, pkgs, lib, ...}:
{
  environment.sessionVariables = {
  OPENROUTER_API_KEY = "$(cat /home/jane/.config/zed/openrouter_api_key)";
  };
}
