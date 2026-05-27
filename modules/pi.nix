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
    ".pi/agent/extensions/tool-use-enforcement.ts".text = ''
      import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

      export default function (pi: ExtensionAPI) {
        pi.on("beforeResponse", (event, ctx) => {
          const text = ctx.currentResponse?.text ?? "";
          if (!ctx.hasToolCalls && text.length > 0) {
            if (text.length > 40 && !text.includes("```")) {
              return {
                block: true,
                reason:
                  "Research first. Use tools to verify claims, read files, and gather evidence before answering. Do not produce text-only responses without executing tool calls."
              };
            }
          }
          return { block: false };
        });
      }
    '';

    # Generic agent router — #<agent_id> prefix dispatches to agent definitions in ~/.pi/agents/
    ".pi/agent/extensions/agent-router.ts".text = builtins.readFile ../dotfiles/pi/extensions/agent-router.ts;

    # AGENTS.md — loaded every Pi session
    ".pi/AGENTS.md".text = ''
      ## Core behavior

      - Research before answering. Verify claims with tools before reporting as fact.
      - Use tools on every turn. Do not produce text-only responses without executing tool calls.
      - Show file paths clearly when working with files.
      - Be concise. No filler, no pleasantries.

      ## Workflow

      - Load relevant skills before starting a task.
      - Break complex work into steps.
      - After completing a task, summarize what was done.
      - If you're unsure about something, research it rather than guessing.

      ## Verification

      - When a subagent or tool claims something was done, verify it.
      - Don't take output at face value — check the file was written, check the URL works.

      ## Context

      This is a NixOS system.
      - Missing system tool? Use `nix-shell -p <pkg>` — never apt/pip/npm.
      - Always use isolated envs: Python → venv, Node/bun → local not global, etc.
      - Ask which language tool to use if unsure (bun vs npm, uv vs pip, etc.)

      Terse like caveman. Technical substance exact. Only fluff die.
      Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging.
      Fragments OK. Short synonyms. Code unchanged.
      Pattern: [thing] [action] [reason]. [next step].
      ACTIVE EVERY RESPONSE. No revert after many turns. No filler drift.
      Code/commits/PRs: write normal. Off: "stop caveman" / "normal mode".
    '';
  };
}
