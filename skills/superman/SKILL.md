---
name: superman
description: Structured planning-first workflow — ask clarifying questions, produce a plan, get user approval, then execute. Invoke explicitly with `/superman`.
allowed-tools: Bash Read Write Edit Grep Find Lsp Mcp Subagent WebSearch FetchContent Skill Advisor AskUser
metadata:
  user-invocable: "true"
  argument-hint: "[task description] — asks clarifying questions, plans, gets approval, then executes"
---

# Superman Planning Skill

A skill that enforces a structured planning-first workflow: ask clarifying questions,
produce a plan, get user approval, then execute.

Requires the `pi-ask-user` extension for interactive questioning.

## When to use

Invoke explicitly with `/superman` followed by what you want to do. Do NOT auto-trigger.

## Workflow

### Phase 1 — Clarify

Ask the user follow-up questions using `ask_user` until you have enough context to write
a confident plan. Questions must be dynamically generated — decide what you still don't
know and ask specifically about that. Do not use a fixed script.

Examples of what to probe:
- Constraints (platform, performance, compatibility)
- Preferences (approach, libraries, style)
- Edge cases or ambiguity in the request
- What the user has already tried

After each answer, decide: do you need more info or can you plan now?

### Phase 2 — Plan

Write a plan covering:
- Goal (restated for confirmation)
- Approach / architecture
- Files to create or modify
- Order of operations
- Risks, unknowns, open questions

Present the plan to the user via `ask_user` with three options:
- **Approve** — proceed to Phase 4
- **Feedback** — provide revision notes
- **Deny** — cancel entirely

### Phase 3 — Revise (loop)

If the user gives Feedback:
1. Incorporate the feedback
2. Show the revised plan via `ask_user` again with the same three options
3. Do NOT start implementation — only show the plan
4. Repeat until approved or denied

If the user Denies:
1. Acknowledge and stop
2. Optionally ask if they want to restart from Phase 1

### Phase 4 — Execute

On approval, implement the plan. Follow TDD pattern where applicable: test before code,
verify after write.

## Hard rules

- NEVER start implementation before the user approves the plan
- On feedback, show the revised plan again — do not skip to implementation
- Questions must be dynamic, not templated
- Each `ask_user` call should be one focused question, not multiple crammed in
- If the user's request is already clear enough after the initial message, skip Phase 1
  and go straight to the plan
