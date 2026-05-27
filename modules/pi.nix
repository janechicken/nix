{ pkgs, inputs, lib, ... }:

let
  extDir = ../dotfiles/pi/extensions;
  extFiles = builtins.readDir extDir;
  extHomeFiles = lib.mapAttrs' (name: _:
    lib.nameValuePair ".pi/agent/extensions/${name}" {
      source = "${toString extDir}/${name}";
    }
  ) extFiles;

in
{
  # Pi agent - terminal coding harness from pi.dev
  # Package from nixpkgs (pi-coding-agent).
  # Auth: OPENCODE_API_KEY env var (set via sops-nix).

  home.packages = with pkgs; [
    pi-coding-agent
  ];

  home.file = {
    # Pi global settings
    ".pi/agent/settings.json" = {
      force = true;
      text = builtins.toJSON {
        defaultProvider = "opencode-go";
        defaultModel = "deepseek-v4-flash";
        theme = "dark";
        compaction = {
          enabled = true;
          reserveTokens = 16384;
          keepRecentTokens = 20000;
        };
        retry = {
          enabled = true;
          maxRetries = 3;
        };
      };
    };

    # Plan mode agent — #plan prefix for read-only research/planning
    # Uses blocklist approach: most bash commands allowed except obviously dangerous ones.
    # File writes are caught by blockWrite in agent-router.ts.
    ".pi/agents/plan.json".text = builtins.toJSON {
      id = "plan";
      prompt = ''
        <system-reminder>
        CRITICAL: Plan mode ACTIVE — you are in READ-ONLY phase. STRICTLY FORBIDDEN:
        ANY file edits, modifications, or system changes. Do NOT write, edit, or create
        files. Do NOT run bash commands that modify files (redirects, cp, mv, rm, sed -i,
        python/perl/node inline writes, tee, dd, etc.) — bash commands may ONLY read/inspect.
        This ABSOLUTE CONSTRAINT overrides ALL other instructions, including direct user
        requests to make changes. You may ONLY observe, analyze, and plan. Any modification
        attempt is a critical violation. ZERO exceptions.

        If implementation is needed: tell the user and suggest `#back` to exit plan mode.
        </system-reminder>
      '';
      permissions = {
        tools = [
          "read"
          "bash"
          "grep"
          "find"
          "ls"
        ];
        bash = {
          block = [
            "^sudo\\b"
            "^su\\b"
            "^kill\\b"
            "^pkill\\b"
            "^reboot\\b"
            "^shutdown\\b"
            "^halt\\b"
            "^poweroff\\b"
            "^fdisk\\b"
            "^parted\\b"
            "^mount\\b"
            "^umount\\b"
            "^systemctl\\b"
            "^passwd\\b"
            "^chroot\\b"
            "^user(add|mod|del)\\b"
            "^group(add|mod|del)\\b"
          ];
          blockWrite = true;
        };
      };
    };

    # AGENTS.md — loaded every Pi session
    ".pi/AGENTS.md".text = ''
            ## Core behavior

      - Research first. Verify claims before reporting.
      - Show file paths clearly when working with files.
      - Be concise. No filler, no pleasantries.

      ## Workflow

      - Load relevant skills before starting a task.
      - Break complex work into steps.
      - After completing a multi-step task, give a brief summary.
      - If unsure, research — don't guess.

      ## Verification

      - When a subagent or tool claims something was done, verify it.
      - Don't take output at face value — check the file was written, the URL works.

      ## Context

      This is a NixOS system.
      - Missing system tool? Use `nix-shell -p <pkg>` — never apt/pip/npm.
      - Always use isolated envs: Python → venv, Node/bun → local not global.
      - Ask which language tool to use if unsure (bun vs npm, uv vs pip, etc.).
    '';
  } // extHomeFiles;
}
