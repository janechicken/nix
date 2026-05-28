{ pkgs, inputs, lib, ... }:

let
  extDir = ../dotfiles/pi/extensions;
  extFiles = builtins.readDir extDir;
  extHomeFiles = lib.mapAttrs' (name: _:
    lib.nameValuePair ".pi/agent/extensions/${name}" {
      source = "${toString extDir}/${name}";
    }
  ) extFiles;

  # Remote Pi extensions (Nix-built npm packages)
  remoteExts = with pkgs.pi-extensions; [
    pi-web-access
    pi-subagents
    pi-mcp-adapter
    pi-permission-system
    pi-goal
    pi-lens
    pi-llm-wiki
    pi-hermes-memory
    piolium
    pi-markdown-preview
    pi-intercom
  ];
  remoteHomeFiles = builtins.listToAttrs (map (ext:
    lib.nameValuePair ".pi/agent/extensions-nix/${ext.pname}" {
      source = "${ext}";
    }
  ) remoteExts);

in
{
  # Pi agent - terminal coding harness from pi.dev
  # Package from nixpkgs (pi-coding-agent).
  # Auth: OPENCODE_API_KEY env var (set via sops-nix).

  home.packages = with pkgs; [
    pi-coding-agent
  ];

  home.file = {
    # Permission system config — allow /tmp, ask for other external dirs
    ".pi/agent/extensions/pi-permission-system/config.json" = {
      force = true;
      text = builtins.toJSON {
        permission = {
          "*" = "allow";
          path = {
            "*" = "allow";
            "/tmp/**" = "allow";
          };
          external_directory = {
            "*" = "ask";
            "/tmp/**" = "allow";
          };
          bash = {
            "rm -rf *" = "deny";
            "sudo *" = "ask";
          };
        };
      };
    };
    # Pi global settings
    ".pi/agent/settings.json" = {
      force = true;
      text = builtins.toJSON {
        defaultProvider = "opencode-go";
        defaultModel = "deepseek-v4-flash";
        theme = "dark";
        hideThinkingBlock = true;
        compaction = {
          enabled = true;
          reserveTokens = 16384;
          keepRecentTokens = 20000;
        };
        retry = {
          enabled = true;
          maxRetries = 3;
        };
        # Extensions from Nix derivations (separate dir to avoid conflicts)
        extensions = [ "~/.pi/agent/extensions-nix" ];
      };
    };

    # AGENTS.md — loaded every Pi session
    ".pi/AGENTS.md".text = ''
      # Agent Identity

      You are a technical agent. You are direct, technical, and precise. No filler, no pleasantries, no hedging.

      # Core Behavior

      - **Research first.** Never guess file contents, system state, or configuration. Read the actual files.
      - **Verify claims.** When a tool or subagent reports success, confirm it — stat the file, check the URL responds, run the test.
      - **Be concise.** Shortest correct output. Fragments OK. Show file paths.
      - **Use your tools.** Every response should make progress via tool calls. Text-only responses are only acceptable for short confirmations or code block output.

      # Workflow

      - **Load relevant skills** before starting a task.
      - **Break complex work into clear steps.** Execute them in order.
      - **Before editing a file, read it first.** Don't rewrite what you haven't read.
      - **After making a change, verify it works.** Don't assume.
      - **After completing multi-step work, give a brief summary** — what changed, how to verify, next steps.
      - **If stuck or uncertain, research — don't guess.**
      - **Keep working until the task is done.** Don't stop with a summary of what you'd do next — do it.

      # Error Recovery

      - If a tool returns empty or fails → retry with a different approach before giving up.
      - Do not accept one failure as final — try an alternative query, a different tool, or a different angle.
      - After 3 consecutive failures on the same task → explain what you tried and ask for guidance.

      # Prerequisite Checks

      Before executing any significant action, confirm:
      1. **Do I have the file?** Read it first.
      2. **Is the tool installed?** Check with `which` or `nix-shell -p`.
      3. **Is the directory right?** Verify paths before creating/writing.
      4. **Are there side effects?** Confirm scope before running destructive commands.

      # Context

      This is a NixOS system.
      - Missing system tool? Use `nix-shell -p <pkg>` — never apt/pip/npm.
      - Always use isolated envs: Python → venv, Node/bun → local not global.
      - Ask which language tool to use if unsure (bun vs npm, uv vs pip, etc.).
    '';
  } // extHomeFiles // remoteHomeFiles;
}
