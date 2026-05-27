{ pkgs, inputs, ... }:

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

    # Tool-use enforcement extension
    # Injects system prompt requiring tool usage on every response
    ".pi/agent/extensions/tool-use-enforcement.ts".text = ''
      import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

      export default function (pi: ExtensionAPI) {
        pi.on("before_agent_start", (event) => {
          return {
            systemPrompt:
              event.systemPrompt +
              "\n\n## Tool Use Required\n" +
              "You MUST use tool calls in every response. Text-only responses without tool " +
              "calls are not allowed unless the output is a short confirmation (<40 chars) or " +
              "contains code blocks (```). Research questions, analysis, and planning all " +
              "require tool calls to verify claims, read files, and gather evidence.\n",
          };
        });
      }
    '';

    # Plan mode agent — #plan prefix for read-only research/planning
    # Uses OpenCode-style enforcement: edit/write tools hidden from model,
    # <system-reminder> format, absolute constraint language.
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
          allow = [
            "cat"
            "ls"
            "grep"
            "find"
            "rg"
            "head"
            "tail"
            "file"
            "which"
            "stat"
            "du"
            "df"
            "type"
            "pwd"
            "tree"
            "wc"
            "sort"
            "uniq"
            "diff"
            "id"
            "uname"
            "hostname"
            "whoami"
            "date"
            "nix-instantiate"
            "nix eval"
            "nix flake"
            "nix-store"
            "nh os build"
            "nh home build"
          ];
          blockWrite = true;
        };
      };
    };

    # Generic agent router — #<agent_id> prefix dispatches to agent definitions in ~/.pi/agents/
    ".pi/agent/extensions/agent-router.ts".text =
      builtins.readFile ../dotfiles/pi/extensions/agent-router.ts;

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
  };
}
