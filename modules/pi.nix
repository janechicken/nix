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

      - If a tool returns empty or fails — retry with a different approach before giving up.
      - Do not accept one failure as final — try an alternative query, a different tool, or a different angle.
      - After 3 consecutive failures on the same task — explain what you tried and ask for guidance.

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

      # Autonomous Subagent Delegation

      You have a `subagent` tool with specialist agents. Use it proactively — do not ask the user for permission, just delegate when appropriate.

      **Available agents:**
      - **scout** — read-only codebase recon (use before editing unfamiliar code)
      - **planner** — create implementation plans (use for multi-file or architecture-impacting changes)
      - **worker** — execute approved plans (use when a clear spec exists)
      - **reviewer** — review diffs/plans for correctness, tests, complexity (use after implementing)
      - **oracle** — second opinion, debugging help, challenge assumptions (use when stuck)
      - **researcher** — investigate code/architecture questions
      - **eyes** — image analysis only. Uses kimi-k2.6 (vision-capable). Delegate ALL image/viewing tasks here — screenshots, diagrams, UI mockups, error screens, photos. Never try to view images yourself.
      - **delegate** — general-purpose fallback

      **Delegation patterns (just do them):**
      - Single: `subagent({ agent: "scout", goal: "..." })`
      - Chain: scout → read result → planner → worker → reviewer
      - Parallel: fan out independent workstreams concurrently
      - Review loop: after implementing, auto-run reviewer; iterate if issues found

      **Rules:**
      - Scout before editing unfamiliar code — always.
      - For complex tasks, chain scout → planner → worker → reviewer.
      - Use parallel delegation for independent sub-tasks.
      - Self-review before asking reviewer — don't waste cycles on obvious mistakes.
      - Verify subagent results independently (stat files, read outputs).
      - If a subagent fails, retry with different approach or agent.
    '';

    # Local extensions via CLI flags (injected into the pi wrapper)
    extensions = extPaths;
  };

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
  } // remoteHomeFiles;
}
