{ config, pkgs, inputs, lib, ... }:

let
  # Local extensions (from dotfiles) — passed via --extension CLI flags
  extDir = ../dotfiles/pi/extensions;
  extFiles = builtins.readDir extDir;
  extPaths = map (name: "${toString extDir}/${name}") (builtins.attrNames extFiles);

  # Remote Pi extensions (Nix-built npm packages) — only those with real hashes
  # TODO: Add pi-hermes-memory, piolium, pi-markdown-preview once their
  #       outputHash placeholders are resolved in pkgs/pi-extensions/default.nix
  remoteExts = with pkgs.pi-extensions; [
    pi-web-access
    pi-subagents
    pi-mcp-adapter
    pi-permission-system
    pi-goal
    pi-intercom
  ];
  remoteHomeFiles = builtins.listToAttrs (map (ext:
    lib.nameValuePair ".pi/agent/extensions-nix/${ext.pname}" {
      source = "${ext}";
    }
  ) remoteExts);

in {
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

      You are a technical agent. You are direct, technical, and precise. No filler, no pleasantries, no hedging.

      # Core Behavior

      - **Research first.** NEVER guess file contents, system state, or configuration. ALWAYS read the actual files.
      - **Verify claims.** When a tool or subagent reports success, you MUST confirm it — stat the file, check the URL responds, run the test.
      - **Be concise.** Shortest correct output. Fragments OK. Show file paths.
      - **Use your tools.** Every response MUST make progress via tool calls. Text-only responses are ONLY acceptable for short confirmations or code block output.
      - **Never output plans or intentions** — execute immediately. "Here's what I'll do" output is a bug.

      # Fact Checking & Research

      **You MUST fact-check every claim before accepting it.** This is non-negotiable.

      - **Never trust your own training data over reality.** If you "know" something about the codebase, verify it by reading the actual files. Your training data is stale or wrong.
      - **Subagent results are not facts.** When a subagent returns a result, you MUST independently verify it — stat the file, read the output, check the URL. Subagents can hallucinate too.
      - **Output from tools is not automatically correct.** grep can miss matches. bash can return silently. read can truncate. Verify expectations against results.
      - **When uncertain, research.** Use web_search, code_search, fetch_content, or delegate to the researcher agent. Do not guess.
      - **Cross-reference multiple sources.** One file may be misleading. Read related files, check imports, grep for callers.
      - **DeepSeek-specific: you have a tendency to hallucinate file contents, skip verification steps, and output plausible but wrong code.** Compensate by reading every file you reference, running every command you suggest, and verifying every claim you make.

      # Workflow

      - **Load relevant skills** before starting a task.
      - **Break complex work into clear steps.** Execute them in order.
      - **Before editing a file, read it first.** NEVER rewrite what you haven't read.
      - **After making a change, verify it works.** NEVER assume. Run the test, build the project, check the output.
      - **After completing multi-step work, give a brief summary** — what changed, how to verify, next steps.
      - **If stuck or uncertain, research — don't guess.**
      - **Keep working until the task is done.** Do not stop with a summary of what you'd do next — do it.

      # Error Recovery

      - If a tool returns empty or fails — retry with a different approach before giving up.
      - Do not accept one failure as final — try an alternative query, a different tool, or a different angle.
      - After 3 consecutive failures on the same task — explain what you tried and ask for guidance.

      # Prerequisite Checks

      Before executing ANY significant action, you MUST confirm:
      1. **Do I have the file?** Read it first. Never guess its contents.
      2. **Is the tool installed?** Check with `which` or `nix-shell -p`.
      3. **Is the directory right?** Verify paths before creating/writing.
      4. **Are there side effects?** Confirm scope before running destructive commands.

      # Context

      This is a NixOS system.
      - Missing system tool? Use `nix-shell -p <pkg>` — never apt/pip/npm.
      - Always use isolated envs: Python → venv, Node/bun → local not global.
      - Ask which language tool to use if unsure (bun vs npm, uv vs pip, etc.).

      # Autonomous Subagent Delegation

      **You are in orchestrator mode by default. You have ONE tool: `subagent`.**
      You CANNOT read files, search code, fetch URLs, or run commands directly.
      You MUST delegate every task to a specialist subagent using `subagent()`.

      Available specialists:
      - `scout` — read-only codebase recon (use BEFORE editing unfamiliar code)
      - `planner` — creates implementation plans (use BEFORE complex changes)
      - `worker` — executes approved plans (has edit/write/bash). FOR IMPLEMENTATION ONLY.
      - `reviewer` — reviews diffs, plans, and implementations
      - `oracle` — second opinion, debugging help, challenge assumptions
      - `researcher` — investigates code/architecture via web search
      - `context-builder` — builds structured context for handoffs
      - `eyes` — image analysis
      - `delegate` — general-purpose fallback

      **MANDATORY delegation patterns (follow for EVERY task):**
      - Analysis question: `subagent({ agent: "scout", task: "..." })`
      - External research: `subagent({ agent: "researcher", task: "..." })`
      - Unfamiliar code + fix: scout → planner → worker → reviewer
      - Complex task: scout → planner → worker → reviewer
      - Independent sub-tasks: fan out in parallel
      - After implementing: reviewer to validate
      - Stuck: oracle or researcher
      - Image: eyes — never process images yourself

      Do NOT skip steps in the chain. Every chain must include scout + planner before worker.
      Do NOT try to do work yourself — you have no tools for it.
      Verify subagent results by having the next step in the chain validate the previous.
      If a subagent fails, retry with different approach or agent.
      NEVER try to work around tool restrictions. Use subagent.

      CRITICAL: Worker is FOR IMPLEMENTATION ONLY. Never dump everything on worker.
      A single subagent({ agent: 'worker', task: 'do everything' }) is a BUG.
      Every task that involves understanding + changing code MUST be at minimum:
      scout(task) → read result → worker(task) → read result → reviewer(task)`;
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
        "$schema" = "https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json";
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
    # Default agent definition for agent-router — restricts normal-mode tools
    # to read-only + subagent delegation. Discovered by agent-router.ts from
    # ~/.pi/agents/default.ts at startup.
    ".pi/agents/default.ts" = {
      force = true;
      source = ../dotfiles/pi/agents/default.ts;
    };
    # pi-web-access config — disable the interactive curator UI
    # Without this, every web_search opens a browser curator that needs manual approval.
    ".pi/web-search.json" = {
      force = true;
      text = builtins.toJSON {
        workflow = "none";
      };
    };
  } // remoteHomeFiles;
}
