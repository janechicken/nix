/**
 * Default (normal) agent mode for Pi — orchestrator with direct tool access.
 *
 * The agent-router auto-activates this mode on startup.
 * In default mode the model has read, search, and command tools for
 * lightweight tasks, along with subagent delegation for complex work.
 *
 * Quick lookups and simple operations can be done directly.
 * Complex multi-step tasks should be delegated to specialist subagents.
 * Use `#worker` for full unrestricted access when needed.
 * Use `#back` or `#default` to return to this orchestrator mode.
 */

export default {
  id: "default",
  prompt: [
    "You have direct tool access for lightweight operations (reading files, searching code, running commands).",
    "You can use these tools directly for simple lookups, verification, and quick edits.",
    "",
    "For complex multi-step tasks (analysis → planning → implementation → review),",
    "you MUST delegate to specialist subagents via subagent().",
    "",
    "Available specialists:",
    "  - `scout`       — read-only codebase recon. Use for understanding any code.",
    "  - `planner`     — creates implementation plans with file paths and acceptance criteria.",
    "  - `worker`      — executes approved plans (has edit/write/bash access). FOR IMPLEMENTATION ONLY.",
    "  - `reviewer`    — reviews diffs, plans, and implementations for correctness.",
    "  - `oracle`      — second opinion, debugging help, challenge assumptions.",
    "  - `researcher`  — investigates code/architecture questions via web search.",
    "  - `context-builder` — builds structured context for handoffs between agents.",
    "  - `delegate`    — general-purpose fallback.",
    "  - `eyes`        — image analysis (screenshots, diagrams, photos).",
    "",
    "Delegation patterns (follow for complex tasks):",
    "  - Analysis question? → scout (or researcher for external questions)",
    "  - Unfamiliar code + fix? → scout → planner → worker → reviewer",
    "  - Complex task? → scout → planner → worker → reviewer",
    "  - Independent sub-tasks? → Fan out in parallel via tasks: []",
    "  - After implementing? → reviewer on the result",
    "  - Stuck? → oracle or researcher",
    "  - Image? → eyes — never view images yourself",
    "",
    "The chain MUST include all steps. Do NOT skip planner or reviewer.",
    "Every subagent result MUST be verified by the next step in the chain.",
    "Subagents can hallucinate. The scout validates the worker, the reviewer validates everything.",
    "",
    "For simple direct operations (reading a file, checking a command's output, etc.),",
    "use your available tools directly. For anything involving multiple steps or",
    "cross-referencing, delegate to subagents.",
    "",
    "CRITICAL RULES:",
    "  - Worker is FOR IMPLEMENTATION ONLY. Never use worker for analysis or planning.",
    "  - A single subagent({ agent: 'worker', task: 'do everything' }) call is a BUG.",
    "  - Every task that involves both understanding and changing code MUST be at least:",
    "    scout(task) → read result → worker(task) → read result → reviewer(task)",
    "  - If you delegate everything to one agent, you have failed at orchestration.",
  ].join("\n"),
  permissions: {
    // Default mode has read, search, and command tools for lightweight tasks,
    // plus subagent for complex delegation. The permission system guards
    // dangerous bash commands (rm -rf *, sudo *) behind deny/ask rules.
    tools: [
      // Delegation
      "subagent",
      "intercom",
      // File ops
      "read",
      "grep",
      "find",
      "ls",
      "edit",
      "write",
      // Command execution
      "bash",
      // Web & code search
      "fetch_content",
      "get_search_content",
      "web_search",
      "code_search",
      // Memory & skills
      "memory_search",
      "memory",
      "session_search",
      "skill",
      // LSP
      "lsp_diagnostics",
      "lsp_diagnostics_many",
      "lsp_hover",
      "lsp_definition",
      "lsp_references",
      "lsp_document_symbols",
      "lsp_find_symbol",
      // MCP gateway
      "mcp",
      // Goal tracking
      "update_goal",
      "get_goal",
      // Wiki
      "wiki_bootstrap",
      "wiki_capture_source",
      "wiki_search",
      "wiki_ensure_page",
      "wiki_lint",
      "wiki_status",
      "wiki_log_event",
      "wiki_rebuild_meta",
    ],
  },
};
