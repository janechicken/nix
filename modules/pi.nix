{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

let
  # Local extensions (from dotfiles) — passed via --extension CLI flags
  extDir = ../dotfiles/pi/extensions;
  extFiles = builtins.readDir extDir;
  extPaths = map (name: "${toString extDir}/${name}") (builtins.attrNames extFiles);

  # Remote Pi extensions (Nix-built npm packages) — only those with real hashes
  remoteExts = with pkgs.pi-extensions; [
    pi-web-access
    pi-subagents
    pi-mcp-adapter
    pi-permission-system
    pi-goal
    pi-hermes-memory
    pi-lsp
    pi-timestamps
    pi-advisor
  ];
  remoteHomeFiles = builtins.listToAttrs (
    map (
      ext:
      lib.nameValuePair ".pi/agent/extensions-nix/${ext.pname}" {
        source = "${ext}";
      }
    ) remoteExts
  );

in
{
  imports = [ inputs.pi-nix.homeManagerModules.default ];

  # Pi agent - terminal coding harness from pi.dev
  # Package: pi.nix (github:lukasl-dev/pi.nix) — proper buildNpmPackage build,
  #          Cachix binary cache (pi.cachix.org)
  # Auth: OPENCODE_API_KEY env var (set via sops-nix).
  programs.pi.coding-agent = {
    enable = true;

    # Rules replaces AGENTS.md (injected via --append-system-prompt)
    # Pi auto-loads rules from this option instead of ~/.pi/AGENTS.md
    rules = ''
      # Agent Identity

      You are a technical agent. Direct, precise, no filler.

      # YOUR KNOWN FAILURE MODES (you will do these unless you actively override)

      You are DeepSeek. Your built-in tendencies:
      - You will write code from memory instead of reading the file first.
      - You will claim a file exists/has certain content without confirming.
      - You will propose fixes without running them.
      - You will output "here's what I'd do next" instead of doing it.

      These are not hypothetical — you do them every session. Compensate consciously.

      # Hard Rules (not suggestions)

      - EVERY file you reference: you MUST have read it in the last 3 messages.
        If you haven't, read it again before saying anything about its contents.
      - EVERY command you run: check its output before proceeding. If it errors,
        stop and fix before moving on.
      - EVERY write you make: immediately read the file back and confirm it
        contains what you intended.
      - EVERY subagent/tool result: treat as unconfirmed until YOU verify it.
        Stat the file. Check the output. Run the test.
      - NEVER end a turn with plans or "next steps." The last thing you output
        must be an executable action or a result.
      - NEVER output a code block you haven't read from the actual file.
        This is the #1 thing you get wrong.
      - If you don't know something or aren't sure: look it up online. Do not
        guess from training data. Use web_search or fetch_content.

      # Delegation (default to delegate, justify if not)

      Default to delegating non-trivial work to subagents. They keep their
      own context windows so yours stays focused.

      Available specialists via subagent():
      - `researcher`  — web research, docs, protocols
      - `scout`       — read-only codebase recon
      - `planner`     — implementation plans
      - `worker`      — full-tool implementation
      - `reviewer`    — code review
      - `oracle`      — second opinion / debugging
      - `delegate`    — general-purpose
      - `eyes`        — image analysis

      Consider delegation first. If you can justify why doing it directly
      is faster and the task is simple enough (single grep, quick read,
      one-line fix), work directly. Otherwise delegate.

      Hard boundaries (known failure modes):
      - **5-tool-call rule**: If after 5 sequential direct tool calls the
        task isn't done and spans multiple repos/docs/web sources, stop
        and fan out to subagents. Don't let iterative-discovery illusion
        keep everything in one context.
      - **2+ independent sources**: Any task involving 2+ independent
        research sources (web searches, GitHub fetches, docs from
        different repos) must be delegated via parallel fan-out. Don't
        chain them sequentially.
      - **Synthesis = delegate**: Any task whose output is a comprehensive
        document synthesizing multiple sources must be delegated to
        planner or oracle. Don't hold 20+ sources in one context.

      # Context

      This is a NixOS system.
      - Missing system tool? Use `nix-shell -p <pkg>` — never apt/pip/npm.
      - Always use isolated envs: Python → venv, Node/bun → local not global.
    '';

    # Local extensions via CLI flags (injected into the pi wrapper)
    extensions = extPaths;
  };

  home.file = {
    # Permission system config — allow everything except destructive ops
    ".pi/agent/extensions/pi-permission-system/config.json" = {
      force = true;
      text = builtins.toJSON {
        permission = {
          "*" = "allow";
          bash = {
            "rm -rf *" = "deny";
            "sudo *" = "ask";
          };
        };
      };
    };

    # Pi global settings
    # Provider/model from sops-nix OPENCODE_API_KEY env var
    ".pi/agent/settings.json" = {
      force = true;
      text = builtins.toJSON {
        defaultProvider = "opencode-go";
        defaultModel = "deepseek-v4-flash";
        theme = "autumn-dark";
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
        # Extensions from Nix derivations (separate dir to avoid conflicts with
        # local extensions passed via --extension CLI flags)
        extensions = [ "~/.pi/agent/extensions-nix" ];
      };
    };

    # Pi theme — derived from Helix autumn-dark-custom
    ".pi/agent/themes/autumn-dark.json" = {
      force = true;
      text = builtins.toJSON {
        "$schema" =
          "https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json";
        name = "autumn-dark";
        vars = {
          red = "#F05E48";
          green = "#99be70";
          yellow = "#FAD566";
          yellow2 = "#ffff9f";
          turquoise = "#86c1b9";
          turquoise2 = "#72a59e";
          text = "#F3F2CC";
          comment = "#626C66";
          bg0 = "#090909";
          bg1 = "#0e0e0e";
          bg2 = "#1a1a1a";
          bg3 = "#404040";
          brown = "#cfba8b";
          fg6 = "#aaaaaa";
          fg7 = "#c4c4c4";
        };
        colors = {
          accent = "red";
          border = "red";
          borderAccent = "turquoise";
          borderMuted = "comment";
          success = "green";
          error = "red";
          warning = "yellow2";
          muted = "comment";
          dim = "#626C66";
          text = "text";
          thinkingText = "comment";
          selectedBg = "bg3";
          userMessageBg = "bg2";
          userMessageText = "";
          customMessageBg = "bg2";
          customMessageText = "";
          customMessageLabel = "yellow";
          toolPendingBg = "bg2";
          toolSuccessBg = "#1a2a1a";
          toolErrorBg = "#2a1a1a";
          toolTitle = "yellow";
          toolOutput = "";
          mdHeading = "yellow";
          mdLink = "turquoise";
          mdLinkUrl = "turquoise2";
          mdCode = "green";
          mdCodeBlock = "";
          mdCodeBlockBorder = "bg3";
          mdQuote = "brown";
          mdQuoteBorder = "brown";
          mdHr = "comment";
          mdListBullet = "turquoise";
          toolDiffAdded = "green";
          toolDiffRemoved = "red";
          toolDiffContext = "comment";
          syntaxComment = "comment";
          syntaxKeyword = "red";
          syntaxFunction = "yellow";
          syntaxVariable = "text";
          syntaxString = "green";
          syntaxNumber = "turquoise";
          syntaxType = "text";
          syntaxOperator = "text";
          syntaxPunctuation = "text";
          thinkingOff = "comment";
          thinkingMinimal = "turquoise";
          thinkingLow = "green";
          thinkingMedium = "yellow";
          thinkingHigh = "red";
          thinkingXhigh = "#ff0000";
          bashMode = "yellow";
        };
      };
    };
    # Eyes subagent — kimi-k2.6 vision agent for image analysis
    ".pi/agent/agents/eyes.md" = {
      force = true;
      source = ../dotfiles/pi/agents/eyes.md;
    };
    # Researcher subagent — web research with web_search + fetch_content
    # Overrides pi-subagents built-in which may not include web tools
    ".pi/agent/agents/researcher.md" = {
      force = true;
      source = ../dotfiles/pi/agents/researcher.md;
    };
    # Planner subagent — creates implementation plans
    # Override removes output: plan.md so it doesn't auto-write unless asked
    ".pi/agent/agents/planner.md" = {
      force = true;
      source = ../dotfiles/pi/agents/planner.md;
    };
    # Context-builder subagent — gathers code context for handoff
    # Override removes output: context.md so it doesn't auto-write unless asked
    ".pi/agent/agents/context-builder.md" = {
      force = true;
      source = ../dotfiles/pi/agents/context-builder.md;
    };
    # Scout subagent — fast codebase recon
    # Override removes output: context.md so it doesn't auto-write unless asked
    ".pi/agent/agents/scout.md" = {
      force = true;
      source = ../dotfiles/pi/agents/scout.md;
    };
    # Default agent definition for agent-router
    ".pi/agents/default.ts" = {
      force = true;
      source = ../dotfiles/pi/agents/default.ts;
    };
    # Plan mode agent — #plan for read-only research/planning
    # Restricts tools to read-only and blocks write operations.
    ".pi/agents/plan.json" = {
      force = true;
      source = ../dotfiles/pi/agents/plan.json;
    };
    # pi-web-access config — disable the interactive curator UI
    # Without this, every web_search opens a browser curator that needs manual approval.
    ".pi/web-search.json" = {
      force = true;
      text = builtins.toJSON {
        workflow = "none";
      };
    };
    # pi-advisor config — default to deepseek-v4-pro via opencode-go
    # Overrides the extension's built-in default (anthropic/claude-fable-5).
    # maxContextMessages is high because deepseek-v4-pro has a massive context
    # window — the advisor needs the full conversation to give strategic advice.
    # maxTokens is generous because reasoning="high" counts thinking tokens
    # against the output budget; 32K leaves room for CoT + actionable verdict.
    ".pi/agent/advisor.json" = {
      force = true;
      text = builtins.toJSON {
        enabled = true;
        provider = "opencode-go";
        model = "deepseek-v4-pro";
        maxUsesPerRun = 3;
        maxTokens = 32768;
        reasoning = "high";
        maxContextMessages = 200;
      };
    };
  }
  // remoteHomeFiles;
}
