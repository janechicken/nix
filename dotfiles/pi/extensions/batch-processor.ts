/**
 * /batch — Parallel batch processor for Pi.
 *
 * Three composable subcommands:
 *   /batch scrape <url>         — scrape challenges via web fetch or MCP
 *   /batch index <dir> [prompt]  — index local files, attach a goal prompt per item
 *   /batch list                  — show currently indexed items
 *   /batch act                   — fan out multi-agent chains on all indexed items
 *
 * Each act task runs an internal chain per item:
 *   scout(item) → planner(scout + goal) → worker(plan) → reviewer(result)
 *
 * Items stored at ~/.pi/batch/items.json
 *   Each item has: id, name, category?, difficulty?, files[], description, goal
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";
import * as path from "node:path";

const BATCH_DIR = path.join(process.env.HOME || "/home/jane", ".pi", "batch");
const ITEMS_PATH = path.join(BATCH_DIR, "items.json");

interface BatchItem {
  id: string;
  name: string;
  category?: string;
  difficulty?: string;
  files: string[];
  description: string;
  goal: string;
}

function ensureDir() {
  if (!fs.existsSync(BATCH_DIR)) fs.mkdirSync(BATCH_DIR, { recursive: true });
}

function loadItems(): BatchItem[] {
  if (!fs.existsSync(ITEMS_PATH)) return [];
  try {
    return JSON.parse(fs.readFileSync(ITEMS_PATH, "utf-8"));
  } catch { return []; }
}

function saveItems(items: BatchItem[]) {
  ensureDir();
  fs.writeFileSync(ITEMS_PATH, JSON.stringify(items, null, 2) + "\n");
}

export default function (pi: ExtensionAPI) {
  pi.registerSlashCommand({
    name: "batch",
    subcommands: {
      scrape: {
        description: "Scrape challenges from a URL and index them",
        args: [
          { name: "url", type: "string", required: true },
          { name: "prompt", type: "string", required: false },
        ],
        async handler(args: Record<string, string>) {
          const url = args.url;
          const prompt = args.prompt || "solve this challenge";
          return {
            action: "transform",
            text: [
              `Scrape challenges from ${url} then save them as indexed items.`,
              `Use available tools (fetch_content, MCP, or browser) to access the page.`,
              `Extract each challenge as a structured item and save to ${ITEMS_PATH}.`,
              `Each item MUST have: id, name, category, difficulty, files[], description, goal.`,
              `The goal field for every item should be: "${prompt}"`,
              `After scraping, save and report what was found.`,
            ].join("\n"),
          };
        },
      },

      index: {
        description: "Index files in a directory as batch items with a goal prompt",
        args: [
          { name: "dir", type: "string", required: true },
          { name: "prompt", type: "string", required: true },
        ],
        async handler(args: Record<string, string>) {
          const dir = args.dir;
          const prompt = args.prompt;
          if (!fs.existsSync(dir)) {
            return { action: "respond", text: `Error: Directory not found: ${dir}` };
          }
          return {
            action: "transform",
            text: [
              `Index files in ${dir} as batch items.`,
              `Read each file, extract a structured description.`,
              `Save items to ${ITEMS_PATH} as JSON array.`,
              `Each item MUST have: id, name, category?, difficulty?, files[], description, goal.`,
              `The goal field for every item should be: "${prompt}"`,
              `After indexing, report what was found.`,
            ].join("\n"),
          };
        },
      },

      list: {
        description: "Show currently indexed batch items",
        async handler() {
          const items = loadItems();
          if (items.length === 0) {
            return { action: "respond", text: "No items indexed. Use /batch scrape or /batch index first." };
          }
          const lines = items.map((item, i) =>
            `  ${i + 1}. [${item.category || "?"}] ${item.name}${item.difficulty ? ` (${item.difficulty})` : ""}`
          );
          return { action: "respond", text: `**${items.length} indexed items:**\n${lines.join("\n")}\n\nUse /batch act to process them.` };
        },
      },

      act: {
        description: "Run multi-agent chains on all indexed items in parallel",
        async handler() {
          const items = loadItems();
          if (items.length === 0) {
            return { action: "respond", text: "No items to act on. Use /batch scrape or /batch index first." };
          }
          const taskDefs = items.map((item, i) => {
            const desc = [
              `Item: ${item.name}`,
              item.category ? `Category: ${item.category}` : null,
              item.difficulty ? `Difficulty: ${item.difficulty}` : null,
              `Description: ${item.description}`,
              item.files?.length ? `Files: ${item.files.join(", ")}` : null,
              `Goal: ${item.goal}`,
            ].filter(Boolean).join("\n");
            return [
              `{`,
              `  agent: "scout",`,
              `  task: [\`Gather context for: ${item.name}\`,`,
              `    \`${desc.replace(/`/g, "'")}\`,",
              `    "Read all available files and understand the challenge."`,
              `  ].join("\\n")`,
              `},`,
              `{`,
              `  agent: "planner",`,
              `  task: [\`{previous}\\n\\nPlan approach for: ${item.name}\`,`,
              `    \`Goal: ${item.goal.replace(/`/g, "'")}\`,`,
              `    "Create a step-by-step plan with specific commands and file paths."`,
              `  ].join("\\n")`,
              `},`,
              `{`,
              `  agent: "worker",`,
              `  task: [\`{previous}\\n\\nImplement plan for: ${item.name}\`,`,
              `    "Execute the plan. Solve the challenge. Produce the result.",`,
              `    "Verify your solution works before reporting."`,
              `  ].join("\\n")`,
              `},`,
              `{`,
              `  agent: "reviewer",`,
              `  task: [\`{previous}\\n\\nReview implementation for: ${item.name}\`,``,
              `    "Verify correctness. Check for edge cases. Report pass/fail with evidence."`,
              `  ].join("\\n")`,
              `}`,
            ].join("\n");
          });

          const taskArray = taskDefs.map((t, i) => `    [\n${t}\n    ]`).join(",\n");

          return {
            action: "transform",
            text: [
              `Processing ${items.length} items in parallel. For EACH item, chain: scout → planner → worker → reviewer.`,
              ``,
              `Run:`,
              `subagent({`,
              `  chain: [`,
              `    { parallel: [`,
              taskArray,
              `    ], concurrency: 3 }`,
              `  ],`,
              `  context: "fresh"`,
              `})`,
              ``,
              `Track which items succeed and fail. For failed items, retry once with oracle.`,
            ].join("\n"),
          };
        },
      },
    },
  });
}
