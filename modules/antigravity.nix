{
  pkgs,
  ...
}:

let
  # ===========================================================================
  # Antigravity-only T3 Code orchestration policy
  #
  # Why this file and not something else (all of it verified against the
  # installed Antigravity 1.4.1 ACP server + `localharness_external` and
  # T3 Code 0.1.8, not guessed):
  #
  # - T3 Code has no user-facing per-provider system prompt. The only text it
  #   appends to an Antigravity session is a hardcoded constant
  #   (`sessionSystemPromptAppend: PULL_REQUEST_LINKING_INSTRUCTIONS`), sent as
  #   `_meta.antigravity.systemPrompt.append`. Not configurable.
  # - T3 runs Antigravity with a *private* `GEMINI_HOME`
  #   (`~/.t3/userdata/providers/antigravity/<sha256(instanceId)>/`), so the
  #   server reads `<profile>/config/*`, not `~/.gemini/config/*`. The only
  #   thing T3 links back from the real `~/.gemini` are the two user *skill*
  #   directories (`linkAntigravityUserSkills`), and it passes them to the Go
  #   harness through `HarnessConfig.skills_paths`.
  # - `~/.gemini/GEMINI.md` is never read. The harness only stats
  #   `$HOME/.gemini/config/rules/` + `$HOME/.gemini/config/rules.json`, and in
  #   the ACP/harness path those parsed rules are *not* rendered into the
  #   prompt (the `sections/user_rules` template is gated on `KeepUserRules`,
  #   which only the cloud CascadeConfig path sets). Verified by stracing the
  #   harness and capturing the real model request with a stub endpoint: a
  #   `rules/AGENTS.md` with `trigger: always_on` was opened, parsed and then
  #   absent from the outgoing `systemInstruction`.
  # - A user *skill* under `~/.gemini/config/skills/<name>/SKILL.md` **is**
  #   injected: its frontmatter name + description land in every Antigravity
  #   `systemInstruction` under "Available skills", and the harness prompt says
  #   to read the SKILL.md before proceeding.
  #
  # So: a skill is the only Antigravity-only, always-present, persistent
  # instruction channel. It reaches Antigravity and nothing else — pi/DeepSeek
  # reads `AGENTS.md` in the project, Claude/Codex use their own config dirs,
  # and T3 links skill dirs only into the Antigravity profile. DeepSeek
  # subagents therefore never see this text and cannot recurse into delegating
  # to themselves.
  #
  # T3 Code picks the link up when it (re)starts the Antigravity provider, so a
  # restart of T3 Code is needed after the first activation.
  # ===========================================================================
  t3DelegateSkill = ''
    ---
    name: t3-delegate
    description: >-
      REQUIRED for every non-trivial request in T3 Code. You are the orchestrator, not the
      worker: call orchestrator_capabilities once per thread, then delegate research, file
      edits, debugging, builds, tests and verification to DeepSeek with delegate_task
      (target providerInstanceId "pi", model "refuseless/deepseek-v4.1-flash-fast",
      options {"thinking":"high"}), and keep only planning, parallel dispatch and review
      here. Read this SKILL.md before you answer anything that needs files or tools.
    ---

    # T3 Code: orchestrate, do not code

    You are Antigravity running inside T3 Code. Antigravity usage is metered
    weekly and expensive. DeepSeek is cheap. So this session is an
    **orchestrator seat**: you plan, dispatch, review and answer — DeepSeek
    does the work.

    ## Default loop for every non-trivial request

    1. `orchestrator_capabilities` — once per thread, before the first
       `delegate_task` (again only after an error or a provider the user named).
    2. Plan briefly (1-3 sentences). Do not start reading the repo yourself.
    3. Dispatch the work:

           delegate_task
             task:   "<goal> — <exact file paths> — <acceptance check> —
                      do the work yourself; start no subagents; report what you
                      changed and what you verified"
             target: { providerInstanceId: "pi",
                       model: "refuseless/deepseek-v4.1-flash-fast",
                       options: { thinking: "high" } }
             role:   research | implementation | review | test | general
             mode:   "async" for independent work, "wait" only when this turn
                     needs the result
             isolation: "worktree" when the child needs its own checkout or PR

    4. Independent tasks go out in parallel — several `delegate_task` calls in
       one block. Do not serialize work that could run side by side.
    5. Review the child's summary. Spot-check the claim that matters (read the
       one file, run the one check) — a summary is not proof.
    6. Report to the user in a few lines: what was done, what was verified,
       what is left. Fix one-line review findings yourself; anything larger
       becomes another delegate.

    ## Delegate all of this

    Research, file reading and editing, debugging, builds, test runs,
    verification, git inspection, log trawling, dependency and docs lookups,
    refactors, migrations.

    ## Do it yourself, without delegating, only when

    - the user explicitly says "do it yourself", "don't delegate", "just
      answer", or names Antigravity as the worker;
    - the answer is a one-liner you already know — no file reads, no tool
      calls, no round trip;
    - the `pi`/DeepSeek provider is unavailable or its delegates fail. Say so
      plainly, then fall back to doing the work here.

    ## Never

    - Never edit code, run builds or tests, or grep the repo yourself while
      DeepSeek is healthy.
    - Never delegate a trivial one-line answer — the round trip costs more than
      answering.
    - Never use `t3_thread_launch` / `create_threads` to delegate; those create
      new top-level threads for the user.
    - Never let a child delegate: every `task` must carry "do the work
      yourself; start no subagents".
    - Never commit or push unless the user asks.
  '';
in
{
  # ===========================================================================
  # Google Antigravity
  #
  # - `pkgs.antigravity-ide` — the agent-first IDE (VS Code fork), built with
  #   nixpkgs' buildVscode. Unfree, binary redistribution.
  # - `pkgs.antigravity-acp` — Google's ACP server (`agy_acp_server`), the
  #   piece agent harnesses such as T3 Code spawn as a provider.
  #
  # Both ship x86_64-linux and aarch64-linux sources in nixpkgs, so no arch
  # gating is needed for jane-pc or yogabook. `nixpkgs.config.allowUnfree` is
  # already set in modules/core.nix / modules/desktop.nix.
  # ===========================================================================
  home.packages = [
    pkgs.antigravity-ide
    pkgs.antigravity-acp
  ];

  # Antigravity user skill — see the comment on `t3DelegateSkill` above.
  # Lives in the real `~/.gemini` because T3 Code symlinks
  # `<antigravity-profile>/config/skills` here and passes it to the harness.
  home.file.".gemini/config/skills/t3-delegate/SKILL.md".text = t3DelegateSkill;
}
