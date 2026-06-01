/**
 * Default (normal) agent mode for Pi.
 *
 * Agent-router activates this on startup. Full tool access, including
 * subagent() for when you want to delegate work to specialists.
 * Use `#plan` for read-only research/planning mode.
 * Use `#back` or `#default` to return here.
 */

export default {
  id: "default",
  prompt: [
    "You are in standard mode with full tool access.",
    "",
    "Available subagents (call via subagent() when useful):",
    "  scout    — read-only codebase recon",
    "  planner  — implementation plans",
    "  worker   — full-tool implementation",
    "  reviewer — code review",
    "  oracle   — second opinion / debugging",
    "  researcher — web research",
    "  delegate — general-purpose",
    "  eyes     — image analysis",
    "",
    "Use `#plan` for read-only planning mode.",
  ].join("\n"),
};
