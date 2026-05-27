/**
 * Generic #agent router extension for Pi.
 *
 * Discovers agent definitions from ~/.pi/agents/ and ./.pi/agents/
 * (.ts and .json files exporting { id, prompt, permissions? }).
 *
 * Usage: `#<agent_id> <message>` — injects agent prompt, restricts tools.
 *        Non-# message resets to normal mode.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import fs from "node:fs";
import path from "node:path";

interface AgentPermissions {
  /** Tool allowlist. Agent can only use these tools. */
  tools?: string[];
  bash?: {
    /** Bash command prefixes to allow (cat, ls, grep, ...). */
    allow?: string[];
    /** Regex patterns to block (rm, dd, sudo, ...). */
    block?: string[];
  };
}

interface AgentDefinition {
  id: string;
  prompt: string;
  permissions?: AgentPermissions;
}

function loadAgents(dir: string): AgentDefinition[] {
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
        data = require(fullPath);
        data = data.default ?? data;
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

export default function (pi: ExtensionAPI) {
  const homeDir = process.env.HOME ?? "/home/jane";
  const scanDirs = [
    path.join(homeDir, ".pi", "agents"),
    path.join(process.cwd(), ".pi", "agents"),
  ];

  const agents = new Map<string, AgentDefinition>();
  for (const dir of scanDirs) {
    for (const agent of loadAgents(dir)) {
      if (!agents.has(agent.id)) agents.set(agent.id, agent);
    }
  }

  let activeAgent: AgentDefinition | null = null;

  pi.on("input", (event) => {
    const match = event.text.match(/^#(\w+)(?:\s+(.*))?$/s);
    if (match) {
      const agentId = match[1];
      const rest = (match[2] ?? "").trim();
      const agent = agents.get(agentId);
      if (agent) {
        activeAgent = agent;
        return { action: "transform", text: rest || "What should I do?" };
      }
    }

    if (activeAgent && !event.text.startsWith("#")) {
      activeAgent = null;
    }

    return { action: "continue" };
  });

  pi.on("before_agent_start", (event) => {
    if (activeAgent) {
      return {
        systemPrompt: event.systemPrompt + "\n\n" + activeAgent.prompt,
      };
    }
  });

  pi.on("tool_call", (event) => {
    if (!activeAgent) return;
    const perms = activeAgent.permissions;
    if (!perms) return;

    const allowedTools = perms.tools ?? Object.keys(perms).filter(k => k !== "tools");
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
    }
  });
}
