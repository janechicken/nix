{
  pkgs,
  ...
}:

{
  # ===========================================================================
  # T3 Code — minimal web GUI / desktop shell for coding agents
  # (https://t3.codes, github:pingdotgg/t3code).
  #
  # Packaged in nixpkgs (`pkgs/t3/t3code`) as an Electron app built from source
  # with pnpm, plus a wrapper that puts the agent CLIs it shells out to on
  # PATH. Both hosts are covered: meta.platforms comes from nodejs, so
  # x86_64-linux and aarch64-linux both build.
  #
  # Defaults from nixpkgs already enable codex + gh + git; the remaining agent
  # CLIs stay off so the closure only grows when asked for.
  # ===========================================================================
  home.packages = [ pkgs.t3code ];
}
