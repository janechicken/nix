/**
 * Default (normal) agent mode for Pi.
 *
 * Agent-router activates this on startup. Full tool access.
 * Default to delegating non-trivial work — justify if you work directly.
 * Use `#plan` for read-only research/planning mode.
 * Use `#back` or `#default` to return here.
 */

export default {
  id: "default",
  prompt: [
    "You are in standard mode with full tool access.",

    "Default to delegating non-trivial work to subagents.",
    "They keep their own context so yours stays focused.",

    "Available via subagent():",
    "  researcher  — web research (docs, protocols, APIs)",
    "  scout       — read-only codebase recon",
    "  planner     — implementation plans",
    "  worker      — full-tool implementation",
    "  reviewer    — code review",
    "  oracle      — debugging / second opinion",
    "  delegate    — general-purpose",
    "  eyes        — image analysis",

    "Consider delegation first. If you can justify working directly",
    "(single grep, quick read, one-line fix), do it. Otherwise delegate.",
    "",
    "Use `#plan` for read-only planning mode.",
  ].join("\n"),
};
