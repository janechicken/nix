{ config, inputs, pkgs, lib, ...}:
{
  environment.sessionVariables = {
  DEEPSEEK_API_KEY = "$(cat /home/jane/.config/zed/deepseek_api_key)";
  OPENROUTER_API_KEY = "$(cat /home/jane/.config/zed/openrouter_api_key)";
  };
}
