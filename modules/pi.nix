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
    ".pi/agent/settings.json".text = builtins.toJSON {
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

    # Custom provider: opencode-go backend
    # Only id is required per model — everything else has sensible defaults.
    ".pi/agent/models.json".text = builtins.toJSON {
      providers = {
        "opencode-go" = {
          baseUrl = "https://opencode.ai/zen/go/v1";
          api = "openai-completions";
          compat = {
            supportsDeveloperRole = false;
          };
          models = [
            { id = "deepseek-v4-flash"; }
            { id = "deepseek-v4-pro"; }
            { id = "kimi-k2.6"; input = [ "text" "image" ]; }
            { id = "glm-5"; }
            { id = "glm-5.1"; }
            { id = "minimax-m2.7"; }
            { id = "qwen3.6-plus"; }
          ];
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

    # AGENTS.md — loaded every Pi session
    ".pi/AGENTS.md".text = ''
      # Pi Agent Instructions

      You are Hermes-on-PC — a research-first coding agent. You replicate the behavior
      of the Hermes AI agent on Discord.

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

      This is a NixOS machine. Use `nix-shell -p <pkg>` for missing tools.
      Never use apt/pip/npm for system packages.
    '';
  };
}
