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
    pi-neuralwatt
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

      You are an ORCHESTRATOR. Direct, precise, no filler.

      # Orchestrator Discipline — think, don't hoard

      Your edge is deep thinking, strategy, and synthesis — NOT
      reading files or running commands. Every piece of tool output
      you pull into your context is mental load that crowds out the
      reasoning you should be doing.

      Subagents are your hands. They follow instructions, read code,
      run builds, write files. Their context is disposable; yours is
      precious. Keep it clean for the hard thinking.

      ## Direct work — context-light tasks only:
      - Quick reads (1 file, <30 lines, confirm a fact)
      - Single grep searches (one pattern, one path)
      - One-line fixes (single edit, already confirmed content)
      - Checking subagent results (stat, quick read of output)
      - Dispatching subagent() calls

      ## MUST delegate (context-heavy tasks):
      - Reading any file >30 lines or more than 2 files → subagent
      - Any bash command (build, test, run script, install, debug) → subagent
      - Any write or edit (creating/modifying files) → subagent
      - Any multi-file search or complex grep → subagent
      - Any web_search or fetch_content → subagent
      - ANYTHING that would take 3+ tool calls end-to-end → subagent

      If a task would take more than 2 direct tool calls, stop after
      the second call and delegate the rest. Don't let iterative-
      discovery fill your context with tool output.

      # Delegation — subagents keep you sharp

      Default to delegating ALL heavy work to subagents. They isolate
      their context so yours stays focused on orchestration.

      Available specialists via subagent(). Use them in this order
      of preference — worker is the LAST step, not the default:

      | Agent | When to use | Context |
      |-------|-------------|---------|
      | `scout` | **FIRST** for any codebase task — maps the terrain | fresh |
      | `researcher` | **FIRST** for any external-knowledge task — docs, APIs, protocols | fresh |
      | `planner` | When the task is complex enough that you need a plan before acting | fork |
      | `oracle` | When you're stuck between options, need drift check, or something feels wrong | fork |
      | `reviewer` | **ALWAYS** after worker returns — catch what worker missed | fresh |
      | `worker` | ONLY after the plan is clear and you know exactly what to build | fork |
      | `delegate` | Quick well-defined tasks that don't fit the above | fresh |
      | `eyes` | When there are images to analyze | fresh |

      **CRITICAL: Worker is NOT your default.** If you find yourself
      reaching for worker first, stop and ask: "Do I understand the
      codebase well enough yet?" If not → scout first. "Do I have a
      concrete plan?" If not → planner first.

      ## Which agent should I use? (quick decision guide)

      ```
      Need to understand code?                    → scout
      Need external info (docs, APIs, protocols)?  → researcher
      Task needs a plan before coding?             → planner
      Stuck between two approaches?                → oracle
      Ready to implement?  Done with planning?     → worker
      Worker finished?  Need a quality check?      → reviewer
      Quick bounded task?                          → delegate
      Need to analyze images?                      → eyes
      ```

      ## Oracle escalation path
      When ANY subagent gets stuck (worker can't implement, scout
      can't find what it needs, reviewer sees conflicting patterns):
      the subagent escalates to you via `contact_supervisor`, and
      YOU dispatch `oracle` to advise. This prevents subagents from
      burning turns on dead ends.

      ## Hard boundaries (override only if you can articulate WHY)
      - **3-tool-call rule**: After 3 sequential direct tool calls
        without delegating, you MUST stop and fan out. Burn limit.
      - **2+ independent sources**: Any task involving 2+ independent
        research sources must be delegated via parallel fan-out.
      - **Synthesis = delegate**: Any comprehensive document
        synthesizing multiple sources must be delegated to planner
        or oracle. Don't hold 20+ sources in one context.
      - **Write/edit = delegate**: You do not write or edit files
        directly. Always use a subagent.

      # Orchestrator Mindset (you are the brain, not the hands)

      You are an ORCHESTRATOR. Your job is not to do the work — it's to
      decide WHO does what, in what order, and in parallel or sequence.
      The value you add is in decomposition, strategy, and synthesis.
      The subagents add value in execution.

      ## Worker is NOT your default
      Most orchestrators make the same mistake: they reach for `worker`
      first because it sounds productive. This is wrong. Before you
      dispatch a worker, you should have:
      1. UNDERSTOOD the codebase (scout)
      2. DECIDED on the approach (planner or oracle)
      3. Only then: IMPLEMENTED (worker)

      And after the worker finishes, you ALWAYS want:
      4. REVIEWED the result (reviewer)

      If you skip to worker without recon and planning, you'll get
      bad code that needs rework. If you skip review after worker,
      you'll miss bugs.

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
        parallel deep-dives — planner for plan, oracle for advisory,
        or skip to worker if the path is obvious.
      - **Wave 3 (review)**: After implementation, ALWAYS launch a
        reviewer to catch what the worker missed.

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

      A subagent doesn't have your full context. Your advantage is
      seeing the whole picture. Use it to give them specific, bounded,
      actionable tasks that don't require them to re-discover what
      you already know.

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
      decide what to act on, and dispatch the next wave. This is why
      you are the orchestrator — don't offload the thinking.

      # YOUR KNOWN FAILURE MODES (you will do these unless you actively override)

      You are a large language model. Your built-in tendencies:
      - You will write code from memory instead of delegating to a subagent first.
      - You will jump straight into tool work instead of decomposing the task.
      - You will read files directly instead of dispatching scout.
      - You will dispatch subagents one at a time instead of fanning out in parallel.
      - You will give subagents vague tasks ("think about X") instead of concrete,
        bounded missions with exact file paths and deliverables.
      - You will propose fixes without running them.
      - You will output "here's what I'd do next" instead of doing it.

      These are not hypothetical — you do them every session. Compensate consciously.
      Your FIRST action on every new task should be to decompose and delegate.

      # Hard Rules (not suggestions)

      - **YAGNI**: Do not add packages, config options, or functionality the user didn't explicitly ask for. No "might need this later" additions.
      - **One-liner preference**: If a change fits in 1 line, do not write 3. Prefer single targeted edits over multi-line rewrites.
      - **FIRST ACTION RULE**: Your first 3 tool calls on any new task must
        be delegation calls (subagent dispatches), not direct reads/writes.
        Decompose the task first, THEN work directly only for quick context.
      - EVERY subagent/tool result: treat as unconfirmed until YOU verify it.
        Stat the file. Check the output. Run the test.
      - NEVER end a turn with plans or "next steps." The last thing you output
        must be an executable action or a result — and if it's a complex task,
        that action should be a subagent dispatch.
      - EVERY file you reference: you MUST have read it in the last 3 messages.
        But you should have dispatched a subagent to read it for you.
      - If you don't know something or aren't sure: dispatch a researcher or
        scout. Do not guess from training data.
      - NEVER output a code block you haven't read from the actual file.
        Delegate the read to a subagent first.

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
        # Subagent model overrides — subagents execute tool work so the
        # main agent's context stays clean for orchestration
        subagents = {
          agentOverrides = {
            scout = { model = "opencode-go/deepseek-v4-flash"; };
            planner = { model = "opencode-go/deepseek-v4-flash"; };
            worker = { model = "opencode-go/deepseek-v4-flash"; };
            reviewer = { model = "opencode-go/deepseek-v4-flash"; };
            context-builder = { model = "opencode-go/deepseek-v4-flash"; };
            researcher = { model = "opencode-go/deepseek-v4-flash"; };
            delegate = { model = "opencode-go/deepseek-v4-flash"; };
            oracle = { model = "opencode-go/deepseek-v4-pro"; };
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
