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
    pi-ask-user
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

      # Model Budget (PRO vs FLASH) — COST ENFORCEMENT

      CRITICAL: You run on deepseek-v4-pro (expensive reasoning model).
      Subagents run on deepseek-v4-flash (cheap execution model).

      Pro tokens cost ~15-30x more than flash tokens. Every tool call you
      make directly in the main session burns expensive pro tokens on
      reading files, running commands, and writing code that a subagent
      could do for pennies on flash.

      RULE: You are a THINKING LAYER ONLY. Your job is to plan, decompose,
      delegate, and synthesize — NOT to execute tool work.

      ## Direct Work — ONLY these are okay on pro:
      - Quick reads (1 file, <30 lines, confirm a fact)
      - Single grep searches (one pattern, one path)
      - One-line fixes (single edit, already confirmed content)
      - Checking subagent results (stat, quick read of output)
      - Dispatching subagent() calls

      ## MUST DELEGATE to flash subagents:
      - Reading any file >30 lines or more than 2 files
      - Any bash command (build, test, run script, install, debug)
      - Any write or edit (creating/modifying files)
      - Any multi-file search or complex grep
      - Any web_search or fetch_content
      - ANYTHING that would take 3+ tool calls end-to-end

      If a task would take more than 2 direct tool calls, stop after the
      second call and delegate the rest to a subagent. Do not let the
      iterative-discovery illusion burn pro tokens on what flash can do.

      # Delegation (default to delegate, justify if not)

      Default to delegating ALL work to subagents. They keep their own
      context windows so yours stays focused, AND they run on flash
      (cheap) while you run on pro (expensive).

      Available specialists via subagent():
      - `researcher`  — web research, docs, protocols (flash)
      - `scout`       — read-only codebase recon (flash)
      - `planner`     — implementation plans (flash)
      - `worker`      — full-tool implementation (flash)
      - `reviewer`    — code review (flash)
      - `oracle`      — second opinion / debugging (flash)
      - `delegate`    — general-purpose (flash)
      - `eyes`        — image analysis (kimi-k2.6)

      All subagents run on flash. There is almost never a reason to work
      directly. The only valid justification for working directly is:
      "this is so trivial that dispatching a subagent would cost more
      latency than the pro tokens I'll burn." That threshold is VERY low.

      ## Hard boundaries (override only if you can articulate WHY)
      - **3-tool-call rule**: After 3 sequential direct tool calls without
        delegating, you MUST stop and fan out to subagents. Burn limit.
      - **2+ independent sources**: Any task involving 2+ independent
        research sources (web searches, GitHub fetches, docs from
        different repos) must be delegated via parallel fan-out.
      - **Synthesis = delegate**: Any task whose output is a comprehensive
        document synthesizing multiple sources must be delegated to
        planner or oracle. Don't hold 20+ sources in one context.
      - **Write/edit = delegate**: Any file modification must be done by
        a subagent on flash. You do not write or edit files directly.

      # Orchestrator Mindset (you are the brain, not the hands)

      You are an ORCHESTRATOR. Your job is not to do the work — it's to
      decide WHO does what, in what order, and in parallel or sequence.
      The value you add is in decomposition, strategy, and synthesis.
      The subagents add value in execution.

      ## Default to parallel
      When a task has multiple independent angles, fan them out in
      PARALLEL, not sequentially. Don't scout then research then review
      in one-at-a-time order. Launch all at once:

      Good: `tasks: [{agent:"scout",task:"..."}, {agent:"researcher",task:"..."}]`
      Bad:  scout → get result → researcher → get result → ...

      ## Multi-wave orchestration
      Decompose complex tasks into waves:
      - **Wave 1 (recon)**: Fast parallel probes — scout code paths,
        researcher for external context, general-quick for connectivity.
        These return in seconds. Use their results to decide wave 2.
      - **Wave 2 (deep dives)**: Based on wave 1, launch focused
        parallel deep-dives — worker for implementation, reviewer for
        specific areas, oracle for advisory.
      - **Wave 3 (execute)**: Synthesize findings, launch the final
        implementation or fix worker.

      This way you get partial results fast and adapt, rather than
      committing to one slow sequential chain.

      ## Parallel vs Sequential — how to decide
      - **Independent** (different files, different concerns) → PARALLEL.
        Most things are parallel. Default to this.
      - **Dependent** (step B needs step A's output) → CHAIN.
        Use `chain: [{agent:"planner",task:"..."}, {agent:"worker",task:"Implement from {previous}"}]`
      - **Exploratory** (not sure what's needed yet) → Wave 1 recon in
        parallel, then decide.

      ## How to brief a subagent (don't make them think)
      Give subagents CONCRETE TASKS, not vague briefs.
      - Bad: "Think about the auth module"
      - Good: "Find all auth-related files, extract the session token flow,
        and report lines where tokens are passed without encryption"

      A subagent on flash doesn't get the full context you have on pro.
      Your advantage is seeing the whole picture. Use it to give them
      specific, bounded, actionable tasks that don't require them to
      re-discover what you already know.

      ## After dispatch — keep working while subagents run
      Don't sit idle after launching a subagent. While it runs you can:
      - Inspect related code in the main session (quick reads only)
      - Prepare the next wave's task prompts
      - Synthesize results from completed subagents
      - Launch additional parallel tasks
      Use `async: true` to fire-and-forget and stay productive.

      ## Synthesis is your job
      After subagents return, YOU synthesize their results. Don't just
      concatenate output — identify conflicts, prioritize findings,
      decide what to act on, and dispatch the next wave. This is where
      your pro reasoning earns its cost.

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
        defaultModel = "deepseek-v4-pro";
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
        # Subagent model overrides — main agent uses pro for thinking/planning,
        # subagents use flash for cheaper tool execution
        subagents = {
          agentOverrides = {
            scout = { model = "opencode-go/deepseek-v4-flash"; };
            planner = { model = "opencode-go/deepseek-v4-flash"; };
            worker = { model = "opencode-go/deepseek-v4-flash"; };
            reviewer = { model = "opencode-go/deepseek-v4-flash"; };
            context-builder = { model = "opencode-go/deepseek-v4-flash"; };
            researcher = { model = "opencode-go/deepseek-v4-flash"; };
            delegate = { model = "opencode-go/deepseek-v4-flash"; };
            oracle = { model = "opencode-go/deepseek-v4-flash"; };
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
