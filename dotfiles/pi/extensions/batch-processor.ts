import type { AutocompleteItem } from "@earendil-works/pi-tui";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";
import * as path from "node:path";

const INDEX_PATH = path.join(process.cwd(), "index.md");

export default function (pi: ExtensionAPI) {
  pi.registerCommand("batch", {
    description: "Batch process items — scrape, index, list, act",
    getArgumentCompletions: (prefix: string): AutocompleteItem[] | null => {
      const subcommands = [
        { value: "scrape ", label: "scrape <url> [prompt] — Scrape items from a URL" },
        { value: "index ", label: "index <dir> [prompt] — Index items from a local directory" },
        { value: "list", label: "list — List indexed items" },
        { value: "act", label: "act — Process all indexed items" },
      ];
      const filtered = subcommands.filter((s) => s.value.startsWith(prefix));
      return filtered.length > 0 ? filtered : null;
    },
    handler: async (args, ctx) => {
      const match = args.match(/^(\w+)(?:\s+(.*))?$/s);
      if (!match) {
        ctx.ui.notify("Usage: /batch <scrape|index|list|act> [args]", "error");
        return;
      }

      const subcommand = match[1];
      const subargs = (match[2] ?? "").trim();
      let text: string | null = null;

      switch (subcommand) {
        case "scrape": {
          const spaceIdx = subargs.indexOf(" ");
          const url = spaceIdx === -1 ? subargs : subargs.slice(0, spaceIdx);
          const prompt = spaceIdx === -1 ? "process each item" : subargs.slice(spaceIdx + 1).trim();
          if (!url) {
            ctx.ui.notify("Usage: /batch scrape <url> [prompt]", "error");
            return;
          }
          text = [
            `Scrape items from ${url}, then create an index markdown file at ${INDEX_PATH}.`,
            ``,
            `1. Access the page using available tools (fetch_content, MCP, or browser).`,
            `2. For EACH item found, write an item section.`,
            `3. The index file format:`,
            ``,
            "```markdown",
            "# Batch Index",
            `Source: ${url}`,
            `Goal: ${prompt}`,
            "",
            "## Item 1: <item name>",
            "- Category: <category>",
            "- Difficulty: <difficulty>",
            "- Files: <relevant files or URLs>",
            "- Description: <brief description>",
            "- Task: <expanded task for this specific item>",
            "```",
            ``,
            `4. For the Task field, do NOT copy the goal verbatim. Read the item,`,
            `   understand what it requires, and write a concrete, actionable task that`,
            `   expands on the prompt. Include specific techniques, tools, or approaches`,
            `   relevant to that item.`,
            ``,
            `5. Save to ${INDEX_PATH} and report the item count.`,
          ].join("\n");
          break;
        }
        case "index": {
          const spaceIdx = subargs.indexOf(" ");
          const dir = spaceIdx === -1 ? subargs : subargs.slice(0, spaceIdx);
          const prompt = spaceIdx === -1 ? "process each item" : subargs.slice(spaceIdx + 1).trim();
          if (!dir) {
            ctx.ui.notify("Usage: /batch index <dir> [prompt]", "error");
            return;
          }
          if (!fs.existsSync(dir)) {
            ctx.ui.notify(`Error: Directory not found: ${dir}`, "error");
            return;
          }
          text = [
            `Index files in ${dir} into a batch markdown file at ${INDEX_PATH}.`,
            ``,
            `1. Read the files in ${dir} and understand each item.`,
            `2. For EACH item found, write an item section.`,
            `3. The index file format:`,
            ``,
            "```markdown",
            "# Batch Index",
            `Source: ${dir}`,
            `Goal: ${prompt}`,
            "",
            "## Item 1: <item name>",
            "- Category: <category if detectable>",
            "- Difficulty: <if detectable>",
            "- Files: <relevant file paths>",
            "- Description: <brief description>",
            "- Task: <expanded task specific to this item>",
            "```",
            ``,
            `4. For the Task field, do NOT copy the goal verbatim. Read and understand`,
            `   each file, then write a concrete, actionable task. Include specific`,
            `   techniques, tools, or approaches relevant to that item.`,
            ``,
            `5. Save to ${INDEX_PATH} and report the item count.`,
          ].join("\n");
          break;
        }
        case "list": {
          if (!fs.existsSync(INDEX_PATH)) {
            ctx.ui.notify("No index file found. Use /batch scrape or /batch index first.", "error");
            return;
          }
          const content = fs.readFileSync(INDEX_PATH, "utf-8");
          const items = content.match(/## Item \d+: .+/g);
          const goalLine = content.match(/Goal: .+/);
          if (!items || items.length === 0) {
            ctx.ui.notify("Index file exists but no items found. Regenerate.", "error");
            return;
          }
          ctx.ui.notify(
            [
              `**${items.length} items indexed**`,
              goalLine?.[0] || "",
              "",
              ...items.map(l => l.replace("## ", "")),
              "",
              "Use /batch act to process them.",
            ].join("\n"),
            "info"
          );
          return;
        }
        case "act": {
          if (!fs.existsSync(INDEX_PATH)) {
            ctx.ui.notify("No index file found. Use /batch scrape or /batch index first.", "error");
            return;
          }
          const content = fs.readFileSync(INDEX_PATH, "utf-8");

          text = [
            `Read ${INDEX_PATH} and process ALL items in it in parallel.`,
            ``,
            `For EACH item, chain: scout → planner → worker → reviewer.`,
            ``,
            `Use subagent with a parallel chain, one task per item:`,
            `  subagent({`,
            `    tasks: [`,
            `      { chain: [{agent:"scout",task:"..."},{agent:"planner",task:"{previous}"},{agent:"worker",task:"{previous}"},{agent:"reviewer",task:"{previous}"}] },`,
            `      ...one per item...,`,
            `    ],`,
            `    concurrency: 3`,
            `  })`,
            ``,
            `Index content:`,
            ``,
            content,
            ``,
            `Track success/fail per item. Retry failed items once with oracle before giving up.`,
            `Report which items succeeded and which need manual review.`,
          ].join("\n");
          break;
        }
        default: {
          ctx.ui.notify("Unknown subcommand. Use: scrape, index, list, or act", "error");
          return;
        }
      }

      if (text !== null) {
        pi.sendUserMessage(text);
      }
    },
  });
}
