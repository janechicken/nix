/**
 * Generic #agent router extension for Pi.
 *
 * Discovers agent definitions from ~/.pi/agents/ and ./.pi/agents/
 * (.ts and .json files exporting { id, prompt, permissions? }).
 *
 * Delegates bash/tool permission enforcement to @gotgenes/pi-permission-system
 * when installed (graceful fallback if not).
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
  /** Tools to hide from the model entirely. */
  hiddenTools?: string[];
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

  // --- Permission system integration ---
  // Lazily resolve the service so agent-router works even if
  // @gotgenes/pi-permission-system isn't installed or loads after us.
  // The service reads from globalThis at call time, so it picks up
  // the published service even if the extension loads after we do.
  let permMod: any;
  async function checkPermission(
    surface: string,
    value?: string,
    agentName?: string,
  ): Promise<{ state: string } | undefined> {
    try {
      if (!permMod) permMod = await import("@gotgenes/pi-permission-system");
      const svc = permMod.getPermissionsService();
      return svc?.checkPermission(surface, value, agentName);
    } catch {
      return undefined;
    }
  }

  // --- Agent routing ---
  pi.on("input", (event, ctx) => {
    const match = event.text.match(/^#(\w+)(?:\s+(.*))?$/s);
    if (match) {
      const agentId = match[1];
      const rest = (match[2] ?? "").trim();

      // Built-in reset commands: #back / #default exit agent mode
      if (agentId === "back" || agentId === "default") {
        if (activeAgent) {
          if (originalTools) {
            pi.setActiveTools(originalTools);
            originalTools = null;
          }
          activeAgent = null;
          ctx.ui.setStatus("agent", undefined);
          return {
            action: "transform",
            text: rest
              ? `Returned to normal mode. ${rest}`
              : "Returned to normal mode.",
          };
        }
        return { action: "continue" };
      }

      const agent = agents.get(agentId);
      if (agent) {
        activeAgent = agent;
        ctx.ui.setStatus("agent", ctx.ui.theme.fg("accent", `#${agentId}`));

        // Apply per-agent tool restrictions
        if (originalTools === null) {
          originalTools = pi.getActiveTools();
        }

        const perms = agent.permissions;
        if (perms) {
          if (perms.tools) {
            pi.setActiveTools(perms.tools);
          } else if (perms.hiddenTools) {
            pi.setActiveTools(
              originalTools.filter(
                (t) => !perms.hiddenTools!.includes(t) && !EDIT_TOOLS.includes(t),
              ),
            );
          }
        }

        return {
          action: "transform",
          text: rest || "What should I do?",
        };
      }
    }

    return { action: "continue" };
  });

  // --- Inject agent prompt as <system-reminder> ---
  pi.on("context", (event) => {
    if (!activeAgent?.prompt) return;

    const lastUserMsg = event.messages.findLast((m) => m.role === "user");
    if (!lastUserMsg) return;

    const reminder = `<system-reminder>\n${activeAgent.prompt.replace(/<\/?system-reminder>/g, "").trim()}\n</system-reminder>`;

    const content = lastUserMsg.content;
    if (typeof content === "string") {
      lastUserMsg.content = content + "\n\n" + reminder;
    } else if (Array.isArray(content)) {
      content.push({ type: "text", text: reminder });
    }

    return { messages: event.messages };
  });

  // --- Runtime enforcement via permission system ---
  pi.on("tool_call", async (event) => {
    if (!activeAgent) return;

    const result = await checkPermission(
      event.toolName === "bash" ? "bash" : event.toolName,
      event.toolName === "bash"
        ? ((event.input as any).command as string)
        : event.toolName,
      activeAgent.id,
    );
    if (result?.state === "deny") {
      return {
        block: true,
        reason: `[agent-router] ${event.toolName} denied in #${activeAgent.id} mode.`,
      };
    }
    // "ask" — the permission system handles prompting via its own UI hooks
  });
}
