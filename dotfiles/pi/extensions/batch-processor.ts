/**
 * /batch — Parallel batch processor for Pi.
 *
 * Three composable subcommands:
 *   /batch scrape <url>     — scrape challenges via web fetch or MCP
 *   /batch index <dir>       — index local files into structured tasks
 *   /batch list              — show currently indexed items
 *   /batch act <prompt>      — fan out multi-agent chains per item
 *
 * Each act task runs an internal chain per item:
 *   scout(item) → planner(scout) → worker(plan) → reviewer(result)
 *
 * Items stored at ~/.pi/batch/items.json
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
  files?: string[];
  description: string;
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
  // --- /batch scrape <url> ---
  pi.registerSlashCommand({
    name: "batch",
    subcommands: {
      scrape: {
        description: "Scrape challenges from a URL and index them",
        args: [{ name: "url", type: "string", required: true }],
        async handler(args: Record<string, string>) {
          const url = args.url;
          return {
            action: "transform",
            text: `Scrape challenges from ${url} then save them as indexed items. Use available tools (fetch_content, MCP, or browser) to access the page, extract each challenge as a structured item with id, name, category, difficulty, and description, then save to ${ITEMS_PATH}. After scraping, report what was found.`,
          };
        },
      },

      // --- /batch index <dir> ---
      index: {
        description: "Index files in a directory as batch items",
        args: [{ name: "dir", type: "string", required: true }],
        async handler(args: Record<string, string>) {
          const dir = args.dir;
          if (!fs.existsSync(dir)) {
            return { action: "respond", text: `Error: Directory not found: ${dir}` };
          }
          return {
            action: "transform",
            text: `Index files in ${dir} as batch items. Read each file, extract a structured description, and save items to ${ITEMS_PATH} as JSON array with id, name, category, difficulty, description per item. After indexing, report what was found.`,
          };
        },
      },

      // --- /batch list ---
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
          return { action: "respond", text: `**${items.length} indexed items:**\n${lines.join("\n")}\n\nUse /batch act <prompt> to process them.` };
        },
      },

      // --- /batch act <prompt> ---
      act: {
        description: "Run multi-agent chains on all indexed items in parallel",
        args: [{ name: "prompt", type: "string", required: true }],
        async handler(args: Record<string, string>) {
          const items = loadItems();
          if (items.length === 0) {
            return { action: "respond", text: "No items to act on. Use /batch scrape or /batch index first." };
          }
          const prompt = args.prompt;
          return {
            action: "transform",
            text: [
              `Processing ${items.length} items in parallel with multi-agent chains.`,
              `For EACH item, run:`,
              `  1. scout → gather context, read files`,
              `  2. planner → create approach based on scout output`,
              `  3. worker → implement solution per plan`,
              `  4. reviewer → validate the result`,
              ``,
              `Chain them using subagent({ chain: [`,
              `  { agent: "scout", task: "Item: [name]. Description: [desc]. Files: [files]. Gather context." },`,
              `  { agent: "planner", task: "{previous} — Plan approach for: [prompt]" },`,
              `  { agent: "worker", task: "{previous} — Implement the plan" },`,
              `  { agent: "reviewer", task: "{previous} — Validate the implementation" }`,
              `], context: "fresh", async: true })`,
              ``,
              `ALL items should run in parallel via one subagent call using tasks:`,
              `subagent({`,
              `  tasks: [`,
              `    { chain: [...item1...] },`,
              `    { chain: [...item2...] },`,
              `    ...`,
              `  ],`,
              `  concurrency: 3`,
              `})`,
              ``,
              `Goal prompt: ${prompt}`,
              ``,
              `Track results — note which items succeeded and which failed.`,
              `For failed items, retry once with oracle before giving up.`,
            ].join("\n"),
          };
        },
      },
    },
  });
}
