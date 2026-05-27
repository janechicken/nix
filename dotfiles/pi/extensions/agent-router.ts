/**
 * Generic #agent router extension for Pi.
 *
 * Discovers agent definitions from ~/.pi/agents/ and ./.pi/agents/
 * (.ts and .json files exporting { id, prompt, permissions? }).
 *
 * Implements OpenCode-style plan mode enforcement:
 * - Hides edit/write tools from the model via setActiveTools()
 * - Injects <system-reminder> blocks into messages via context event
 * - Blocks tool calls at runtime as defense-in-depth
 * - Wraps plan prompts in <system-reminder> tags
 *
 * Usage: `#<agent_id> <message>` — switches to agent mode (sticky).
 *        All subsequent messages stay in that agent mode.
 *        `#back` or `#default` returns to normal mode.
 *        Footer shows `#<agent_id>` when an agent is active.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import fs from "node:fs";
import path from "node:path";

/** OpenCode's edit tool aliases — all map to the "edit" permission key */
const EDIT_TOOLS = ["edit", "write", "apply_patch"];

interface AgentPermissions {
  /** Tool allowlist. Agent can only use these tools. */
  tools?: string[];
  /** Tools to hide from the model entirely (like OpenCode's permission deny). */
  hiddenTools?: string[];
  bash?: {
    /** Bash command prefixes to allow (cat, ls, grep, ...). */
    allow?: string[];
    /** Regex patterns to block (rm, dd, sudo, ...). */
    block?: string[];
    /** If true, block all write operations (redirects, cp, mv, rm, sed -i, etc.). */
    blockWrite?: boolean;
  };
}

interface AgentDefinition {
  id: string;
  prompt: string;
  permissions?: AgentPermissions;
}

async function loadAgents(dir: string): Promise<AgentDefinition[]> {
  const agents: AgentDefinition[] = [];
  if (!fs.existsSync(dir)) return agents;

  for (const file of fs.readdirSync(dir)) {
    const fullPath = path.join(dir, file);
    const ext = path.extname(file);
    if (fs.statSync(fullPath).isDirectory()) continue;

    try {
      let data: any;
      if (ext === ".json") {
        data = JSON.parse(fs.readFileSync(fullPath, "utf-8"));
      } else if (ext === ".ts") {
        const mod = await import(fullPath);
        data = mod.default ?? mod;
      } else {
        continue;
      }
      if (data && data.id) agents.push(data as AgentDefinition);
    } catch (err) {
      console.error("[agent-router] Failed to load", fullPath, err);
    }
  }
  return agents;
}

export default async function (pi: ExtensionAPI) {
  const homeDir = process.env.HOME ?? "/home/jane";
  const scanDirs = [
    path.join(homeDir, ".pi", "agents"),
    path.join(process.cwd(), ".pi", "agents"),
  ];

  const agents = new Map<string, AgentDefinition>();
  for (const dir of scanDirs) {
    for (const agent of await loadAgents(dir)) {
      if (!agents.has(agent.id)) agents.set(agent.id, agent);
    }
  }

  let activeAgent: AgentDefinition | null = null;
  let originalTools: string[] | null = null;

  pi.on("input", (event, ctx) => {
    const match = event.text.match(/^#(\w+)(?:\s+(.*))?$/s);
    if (match) {
      const agentId = match[1];
      const rest = (match[2] ?? "").trim();

      // Built-in reset commands: #back / #default exit agent mode
      if (agentId === "back" || agentId === "default") {
        if (activeAgent) {
          // Restore original tool set
          if (originalTools) {
            pi.setActiveTools(originalTools);
            originalTools = null;
          }
          activeAgent = null;
          ctx.ui.setStatus("agent", undefined);
          return { action: "transform", text: "Returned to normal mode." };
        }
        return { action: "continue" };
      }

      const agent = agents.get(agentId);
      if (agent) {
        activeAgent = agent;
        ctx.ui.setStatus("agent", ctx.ui.theme.fg("accent", `#${agentId}`));

        // --- OpenCode-style tool hiding ---
        // Save current tools before modifying
        if (originalTools === null) {
          originalTools = pi.getActiveTools();
        }

        const perms = agent.permissions;
        if (perms) {
          let activeTools: string[];

          const allowlist = perms.tools;
          const hidden = perms.hiddenTools ?? [];

          if (allowlist) {
            activeTools = [...allowlist];
          } else {
            activeTools = originalTools.filter(
              (t) => !hidden.includes(t) && !EDIT_TOOLS.includes(t),
            );
          }

          pi.setActiveTools(activeTools);
        }

        return {
          action: "transform",
          text: rest || "What should I do?",
        };
      }
    }

    return { action: "continue" };
  });

  // --- Inject <system-reminder> blocks before each LLM call ---
  // Mirrors OpenCode's insertReminders() in session/prompt.ts
  pi.on("context", (event) => {
    if (!activeAgent) return;

    const lastUserMsg = event.messages.findLast((m) => m.role === "user");
    if (!lastUserMsg) return;

    const prompt = activeAgent.prompt;
    if (!prompt) return;

    const reminder = `<system-reminder>\n${prompt.replace(/<\/?system-reminder>/g, "").trim()}\n</system-reminder>`;

    const content = lastUserMsg.content;
    if (typeof content === "string") {
      lastUserMsg.content = content + "\n\n" + reminder;
    } else if (Array.isArray(content)) {
      content.push({ type: "text", text: reminder });
    }

    // CRITICAL: Runner does structuredClone(messages) and only picks up
    // mutations from the return value. In-place mutation is lost.
    return { messages: event.messages };
  });

  // --- OpenCode-style system prompt injection (fallback) ---
  pi.on("before_agent_start", (event) => {
    if (activeAgent && activeAgent.prompt) {
      return {
        systemPrompt:
          event.systemPrompt +
          "\n\n" +
          activeAgent.prompt,
      };
    }
  });

  // --- Runtime tool_call blocker (defense-in-depth) ---
  pi.on("tool_call", (event) => {
    if (!activeAgent) return;
    const perms = activeAgent.permissions;
    if (!perms) return;

    const allowedTools = perms.tools ?? [];

    // OpenCode pattern: deny tools not in allowlist
    if (allowedTools.length > 0) {
      if (!allowedTools.includes(event.toolName)) {
        return {
          block: true,
          reason:
            'Tool "' +
            event.toolName +
            '" not allowed in #' +
            activeAgent.id +
            " mode. Allowed: " +
            allowedTools.join(", "),
        };
      }
    }

    if (event.toolName === "bash" && perms.bash) {
      const cmd = event.input.command as string;

      if (perms.bash.allow?.length) {
        const ok = perms.bash.allow.some((p) => cmd.trim().startsWith(p));
        if (!ok) {
          return {
            block: true,
            reason:
              "Bash command not allowed in #" +
              activeAgent.id +
              " mode. Must start with: " +
              perms.bash.allow.join(", "),
          };
        }
      }

      if (perms.bash.block?.length) {
        const blocked = perms.bash.block.some((p) => new RegExp(p, "i").test(cmd));
        if (blocked) {
          return {
            block: true,
            reason: "Bash command blocked in #" + activeAgent.id + " mode.",
          };
        }
      }

      // Write operation detection — covers actual file-modifying commands
      if (perms.bash.blockWrite) {
        const hasWriteCmd = /\b(cp|mv|rm|dd|install|tee|truncate|fallocate|mkfs|touch|chmod|chown|ln)\b/.test(cmd);
        const hasSedInplace = /\bsed\b\s+-i/.test(cmd);
        const hasPythonFileWrite = /\b(python3?)\s+-c\s+['\"].*(?:open\(.*['\"]w['\"]|\.write\()/.test(cmd);
        const hasPerlFileWrite = /\bperl\s+-[^ ]*e\s+['\"].*(?:open\s*\(.*['\"]>[>]?['\"])/.test(cmd);

        if (hasWriteCmd || hasSedInplace || hasPythonFileWrite || hasPerlFileWrite) {
          return {
            block: true,
            reason: "Write operations not allowed in #" + activeAgent.id + " mode.",
          };
        }
      }
    }
  });
}
