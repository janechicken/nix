/**
 * Default (normal) agent mode for Pi.
 *
 * Agent-router activates this on startup. Full tool access.
 * Use `#plan` for read-only research/planning mode.
 * Use `#back` or `#default` to return here.
 */

export default {
  id: "default",
  prompt: [
    "You are in standard mode with full tool access.",
    "Use `#plan` to switch to read-only planning mode.",
  ].join("\n"),
};
