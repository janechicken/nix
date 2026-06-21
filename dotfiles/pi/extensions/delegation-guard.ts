/**
 * Delegation Guard — hard enforcement of the 3-direct-call rule.
 *
 * Monitors tool calls per LLM turn. After 3 non-subagent tool calls,
 * blocks the 4th with a message forcing delegation.
 *
 * The counter resets each turn (turn_start) and on subagent dispatch
 * so the model gets 3 fresh prep calls per delegation cycle.
 *
 * This prevents the known failure mode where Pi chains 25+ direct
 * grep/read/edit/bash calls without ever delegating to a subagent.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Tools that count as "direct work" — doing stuff yourself instead of delegating
const DIRECT_TOOLS = new Set([
  "read",
  "write",
  "edit",
  "grep",
  "find",
  "ls",
  "bash",
  "web_search",
  "fetch_content",
  "get_search_content",
  "code_search",
  "mcp",
  "lsp_diagnostics",
  "lsp_diagnostics_many",
  "lsp_find_symbol",
  "lsp_hover",
  "lsp_definition",
  "lsp_references",
  "lsp_document_symbols",
  "ask_user",
]);

// Tools that are orchestration helpers — don't count as direct work
const ORCHESTRATION_TOOLS = new Set([
  "subagent",
  "advisor",
  "memory",
  "memory_search",
  "session_search",
  "skill",
  "update_goal",
  "get_goal",
]);

export default function (pi: ExtensionAPI) {
  let directCallCount = 0;

  // Re-arm per-turn: each new LLM turn gets 3 fresh direct calls
  pi.on("turn_start", () => {
    directCallCount = 0;
  });

  pi.on("tool_call", (event) => {
    const toolName = event.toolName;

    // Subagent dispatch = delegation. Reset counter and let it through.
    if (toolName === "subagent") {
      directCallCount = 0;
      return;
    }

    // Orchestration helpers pass through uncounted
    if (ORCHESTRATION_TOOLS.has(toolName)) {
      return;
    }

    // Non-direct tools pass through uncounted
    if (!DIRECT_TOOLS.has(toolName)) {
      return;
    }

    directCallCount++;

    // Hard block on the 4th direct call in one turn
    if (directCallCount > 3) {
      return {
        block: true,
        reason:
          `[DELEGATION-GUARD] Blocked: you've made ${directCallCount - 1} direct ` +
          `tool calls this turn without delegating. The orchestrator rules ` +
          `limit you to 3 direct calls before you MUST dispatch a subagent().\n\n` +
          `Decompose the remaining work and dispatch a scout, worker, ` +
          `researcher, or delegate subagent with a concrete task. ` +
          `After delegation, you'll get 3 fresh direct calls to verify results.`,
      };
    }
  });
}
