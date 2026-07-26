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
  # Unwire delegation-guard (file kept for restore); load other local extensions
  extPaths = map (name: "${toString extDir}/${name}") (
    builtins.filter (name: name != "delegation-guard.ts") (builtins.attrNames extFiles)
  );

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
    pi-neuralwatt
    pi-advisor
    pi-ask-user
    pi-cursor-sdk
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

      Direct, precise coding assistant. No filler.

      # Subagents

      `subagent()` exists. Same model as you — use when parallel work helps (independent recon, research, review, implementation angles). Brief concrete: paths + deliverable. Outputs under `/tmp`, not the project tree. Skip subagents for simple single-path work.

      Available: `scout`, `researcher`, `planner`, `oracle`, `reviewer`, `worker`, `delegate`, `eyes`.

      # Hard Rules

      - **YAGNI**: No packages/options/features user didn't ask for.
      - **One-liner preference**: 1-line fix beats multi-line rewrite when it fits.
      - Verify tool/subagent results before trusting (stat, check output, run test).
      - Never end a turn with plans/"next steps" — end with an executable action or a result.
      - Unknown facts → look them up; do not guess from training data.
      - Never output a code block you haven't read from the actual file.
      - No scratch markdown in project dirs (`progress.md`, `TODO.md`, `NOTES.md`, `*.tmp.md`). Subagent outputs under `/tmp`; delete agent-created scratch `.md` before turn ends. User-requested docs OK.

      # Context

      This is a NixOS system.
      - Missing system tool? Use `nix-shell -p <pkg>` — never apt/pip/npm.
      - Always use isolated envs: Python → venv, Node/bun → local not global.

      # Persistence

      ACTIVE EVERY RESPONSE. No revert after many turns. No filler drift. Still active if unsure. Off only: "stop caveman" / "normal mode".

      Default: **full**. Switch: `/caveman lite|full|ultra`.

      ## Rules

      Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging. Fragments OK. Short synonyms (big not extensive, fix not "implement a solution for"). No tool-call narration, no decorative tables/emoji, no dumping long raw error logs unless asked — quote shortest decisive line. Standard well-known tech acronyms OK (DB/API/HTTP); never invent new abbreviations reader can't decode. Technical terms exact. Code blocks unchanged. Errors quoted exact.

      Preserve user's dominant language. User write Portuguese → reply Portuguese caveman. User write Spanish → reply Spanish caveman. Compress the style, not the language. No forced English openings or status phrases. ALWAYS keep technical terms, code, API names, CLI commands, commit-type keywords (feat/fix/...), and exact error strings verbatim — unless user explicitly ask for translation.

      No self-reference. Never name or announce the style. No "caveman mode on", "me caveman think", no third-person caveman tags. Output caveman-only — never normal answer plus "Caveman:" recap. Exception: user explicitly ask what the mode is.

      Pattern: `[thing] [action] [reason]. [next step].`

      Not: "Sure! I'd be happy to help you with that. The issue you're experiencing is likely caused by..."
      Yes: "Bug in auth middleware. Token expiry check use `<` not `<=`. Fix:"

      ## Intensity

      | Level | What change |
      |-------|------------|
      | **lite** | No filler/hedging. Keep articles + full sentences. Professional but tight |
      | **full** | Drop articles, fragments OK, short synonyms. Classic caveman. No tool-call narration, no decorative tables/emoji, no long raw error-log dumps unless asked. Standard acronyms OK; no invented abbreviations |
      | **ultra** | Abbreviate prose words (DB/auth/config/req/res/fn/impl) — prose words only, never real code symbols/function names. Strip conjunctions, arrows for causality (X → Y), one word when one word enough. Code symbols, function names, API names, error strings: never abbreviate |

      ## Auto-Clarity

      Drop caveman when:
      - Security warnings
      - Irreversible action confirmations
      - Multi-step sequences where fragment order or omitted conjunctions risk misread
      - Compression itself creates technical ambiguity (e.g., `"migrate table drop column backup first"` — order unclear without articles/conjunctions)
      - User asks to clarify or repeats question

      Resume caveman after clear part done.

      Example — destructive op:
      > **Warning:** This will permanently delete all rows in the `users` table and cannot be undone.
      > ```sql
      > DROP TABLE users;
      > ```
      > Caveman resume. Verify backup exist first.

      ## Boundaries

      Code/commits/PRs: write normal. "stop caveman" or "normal mode": revert. Level persist until changed or session end.
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
        defaultProvider = "cursor";
        defaultModel = "grok-4.5";
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
        # Subagent model overrides — subagents execute tool work so the
        # main agent's context stays clean for orchestration
        subagents = {
          agentOverrides = {
            scout = {
              model = "cursor/grok-4.5";
            };
            planner = {
              model = "cursor/grok-4.5";
            };
            worker = {
              model = "cursor/grok-4.5";
            };
            reviewer = {
              model = "cursor/grok-4.5";
            };
            context-builder = {
              model = "cursor/grok-4.5";
            };
            researcher = {
              model = "cursor/grok-4.5";
            };
            delegate = {
              model = "cursor/grok-4.5";
              thinking = "off";
            };
            oracle = {
              model = "cursor/grok-4.5";
            };
            eyes = {
              model = "cursor/grok-4.5";
            };
          };
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
    # Worker subagent — single-writer executor
    # Override adds oracle escalation when stuck or near turn limit
    ".pi/agent/agents/worker.md" = {
      force = true;
      source = ../dotfiles/pi/agents/worker.md;
    };
    # Oracle subagent — advisory on the pro model for smarter reasoning
    # Override adds explicit model frontmatter
    ".pi/agent/agents/oracle.md" = {
      force = true;
      source = ../dotfiles/pi/agents/oracle.md;
    };
    # Eyes subagent — image analysis via cursor/grok-4.5
    ".pi/agent/agents/eyes.md" = {
      force = true;
      source = ../dotfiles/pi/agents/eyes.md;
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
    # pi-advisor config — default to a pro model for strategic advice
    # Overrides the extension's built-in default (anthropic/claude-fable-5).
    # maxContextMessages is high because the pro model has a massive context
    # window — the advisor needs the full conversation to give strategic advice.
    # maxTokens is generous because reasoning="high" counts thinking tokens
    # against the output budget; 32K leaves room for CoT + actionable verdict.
    ".pi/agent/advisor.json" = {
      force = true;
      text = builtins.toJSON {
        enabled = true;
        provider = "cursor";
        model = "grok-4.5";
        maxUsesPerRun = 3;
        maxTokens = 32768;
        reasoning = "high";
        maxContextMessages = 200;
      };
    };

    # Neuralwatt extension settings — enables hidden models (e.g. glm-5.2-short-fast)
    # discovered via the authenticated /v1/models API endpoint.
    # All fields set explicitly to prevent extension migrations from writing to
    # the read-only Nix store symlink.
    ".pi/agent/extensions/neuralwatt.json" = {
      force = true;
      text = builtins.toJSON {
        quotaCommand = true;
        quotaWarnings = true;
        subBarIntegration = true;
        includeLegacyModelIds = false;
        includeHiddenModels = true;
      };
    };
  }
  // remoteHomeFiles;
}
