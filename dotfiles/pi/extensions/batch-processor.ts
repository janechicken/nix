/**
 * /batch — Parallel batch processor for Pi.
 *
 * Subcommands:
 *   /batch scrape <url> [prompt]  — scrape + auto-index into ~/.pi/batch/index.md
 *   /batch index <dir> [prompt]   — index local files into ~/.pi/batch/index.md
 *   /batch list                   — show indexed items
 *   /batch act                    — fan out multi-agent chains per item in index.md
 *
 * Each act task per item: scout(item) → planner(scout+task) → worker(plan) → reviewer(result)
 *
 * Index file format (~/.pi/batch/index.md):
 *   # Batch Index
 *   Source: <url or dir>
 *   Goal: <expanded prompt>
 *
 *   ## Item N: <name>
 *   - Category: ...
 *   - Difficulty: ...
 *   - Files: ...
 *   - Description: ...
 *   - Task: <model-expanded prompt specific to this item>
 *
 * The model expands the goal prompt when writing the md — reads each challenge
 * and writes a specific task per item. Not verbatim copy.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";
import * as path from "node:path";

const INDEX_PATH = path.join(
  process.cwd(),
  "batch", "index.md"
);

export default function (pi: ExtensionAPI) {
  pi.registerSlashCommand({
    name: "batch",
    subcommands: {

      // --- /batch scrape <url> [prompt] ---
      scrape: {
        description: "Scrape challenges from a URL then index them into an md file",
        args: [
          { name: "url", type: "string", required: true },
          { name: "prompt", type: "string", required: false },
        ],
        async handler(args: Record<string, string>) {
          const url = args.url;
          const prompt = args.prompt || "solve each challenge";
          return {
            action: "transform",
            text: [
              `Scrape challenges from ${url}, then create an index markdown file at ${INDEX_PATH}.`,
              ``,
              `1. Access the page using available tools (fetch_content, MCP, or browser).`,
              `2. For EACH challenge found, write an item section.`,
              `3. The index file format:`,
              ``,
              "```markdown",
              "# Batch Index",
              `Source: ${url}`,
              `Goal: ${prompt}`,
              "",
              "## Item 1: <challenge name>",
              "- Category: <category>",
              "- Difficulty: <difficulty>",
              "- Files: <relevant files or URLs>",
              "- Description: <brief description>",
              "- Task: <expanded task for this specific challenge>",
              "```",
              ``,
              `4. For the Task field, do NOT copy the goal verbatim. Read the challenge,`,
              `   understand what it requires, and write a concrete, actionable task that`,
              `   expands on the prompt. Include specific techniques, tools, or approaches`,
              `   relevant to that challenge type.`,
              ``,
              `5. Save to ${INDEX_PATH} and report the item count.`,
            ].join("\n"),
          };
        },
      },

      // --- /batch index <dir> [prompt] ---
      index: {
        description: "Index local files into a batch md file",
        args: [
          { name: "dir", type: "string", required: true },
          { name: "prompt", type: "string", required: false },
        ],
        async handler(args: Record<string, string>) {
          const dir = args.dir;
          const prompt = args.prompt || "solve each challenge";
          if (!fs.existsSync(dir)) {
            return { action: "respond", text: `Error: Directory not found: ${dir}` };
          }
          return {
            action: "transform",
            text: [
              `Index files in ${dir} into a batch markdown file at ${INDEX_PATH}.`,
              ``,
              `1. Read the files in ${dir} and understand each challenge.`,
              `2. For EACH challenge found, write an item section.`,
              `3. The index file format:`,
              ``,
              "```markdown",
              "# Batch Index",
              `Source: ${dir}`,
              `Goal: ${prompt}`,
              "",
              "## Item 1: <challenge name>",
              "- Category: <category if detectable>",
              "- Difficulty: <if detectable>",
              "- Files: <relevant file paths>",
              "- Description: <brief description>",
              "- Task: <expanded task specific to this challenge>",
              "```",
              ``,
              `4. For the Task field, do NOT copy the goal verbatim. Read and understand`,
              `   each file, then write a concrete, actionable task. Include specific`,
              `   techniques, tools, or approaches relevant to that challenge.`,
              ``,
              `5. Save to ${INDEX_PATH} and report the item count.`,
            ].join("\n"),
          };
        },
      },

      // --- /batch list ---
      list: {
        description: "Show currently indexed items",
        async handler() {
          if (!fs.existsSync(INDEX_PATH)) {
            return { action: "respond", text: "No index file found. Use /batch scrape or /batch index first." };
          }
          const content = fs.readFileSync(INDEX_PATH, "utf-8");
          const items = content.match(/## Item \d+: .+/g);
          const goalLine = content.match(/Goal: .+/);
          if (!items || items.length === 0) {
            return { action: "respond", text: "Index file exists but no items found. Regenerate." };
          }
          return {
            action: "respond",
            text: [
              `**${items.length} items indexed**`,
              goalLine?.[0] || "",
              "",
              ...items.map(l => l.replace("## ", "")),
              "",
              "Use /batch act to process them.",
            ].join("\n"),
          };
        },
      },

      // --- /batch act ---
      act: {
        description: "Run multi-agent chains per item from the batch index file",
        async handler() {
          if (!fs.existsSync(INDEX_PATH)) {
            return { action: "respond", text: "No index file found. Use /batch scrape or /batch index first." };
          }

          const content = fs.readFileSync(INDEX_PATH, "utf-8");
          const sections = content.split(/\n(?=## Item \d+: )/);
          const items: Array<{ name: string; task: string }> = [];

          for (const section of sections) {
            if (!section.startsWith("## Item")) continue;
            const nameMatch = section.match(/## Item \d+: (.+)/);
            const taskMatch = section.match(/- Task: (.+)/s);
            if (nameMatch) {
              items.push({
                name: nameMatch[1].trim(),
                task: taskMatch?.[1]?.trim() || "",
              });
            }
          }

          if (items.length === 0) {
            return { action: "respond", text: "No parseable items in the index file." };
          }

          const goalLine = content.match(/Goal: .+/)?.[0] || "";

          // Build a structured task list for the model using subagent chain pattern
          const taskList = items.map((item, i) => {
            return `  ${i + 1}. ${item.name}
     scout: Read files and understand "${item.name}". ${item.task ? `Task: ${item.task}` : ""}
     planner: Based on scout output, create a step-by-step plan.
     worker: Execute the plan. Solve it. Verify.
     reviewer: Validate correctness and completeness.`;
          }).join("\n\n");

          return {
            action: "transform",
            text: [
              `Loaded ${items.length} items from ${INDEX_PATH}.`,
              goalLine,
              ``,
              `Process ALL items in parallel. For EACH item, chain:`,
              `  scout → planner → worker → reviewer`,
              ``,
              `Use subagent with a parallel chain:`,
              `  subagent({`,
              `    tasks: [`,
              `      { chain: [{agent:"scout",task:"..."},{agent:"planner",task:"{previous}"},{agent:"worker",task:"{previous}"},{agent:"reviewer",task:"{previous}"}] },`,
              `      ...one per item...`,
              `    ],`,
              `    concurrency: 3`,
              `  })`,
              ``,
              `Items:`,
              taskList,
              ``,
              `Track success/fail per item. Retry failed items once with oracle before giving up.`,
              `Report which items succeeded and which need manual review.`,
            ].join("\n"),
          };
        },
      },
    },
  });
}
