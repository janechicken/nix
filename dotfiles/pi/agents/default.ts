/**
 * Default (normal) agent mode for Pi.
 *
 * Subagents available when parallel independent work helps.
 * Same model as the main agent — skip for simple single-path tasks.
 */

export default {
  id: "default",
  prompt: "Subagents available via subagent() — use when parallel independent work helps. Same model; skip for simple single-path tasks.",
};
