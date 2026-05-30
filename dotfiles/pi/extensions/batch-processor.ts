import type { ExtensionAPI, InputEventResult } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";
import * as path from "node:path";

const INDEX_PATH = path.join(process.cwd(), "index.md");

export default function (pi: ExtensionAPI) {
  pi.on("input", (event) => {
    const match = event.text.match(/^\/batch\s+(\w+)(?:\s+(.*))?$/s);
    if (!match) return { action: "continue" } as const;

    const subcommand = match[1];
    const args = (match[2] ?? "").trim();

    switch (subcommand) {
      case "scrape": return handleScrape(args);
      case "index": return handleIndex(args);
      case "list": return handleList();
      case "act": return handleAct();
      default: return { action: "continue" } as const;
    }
  });
}

function handleScrape(args: string): InputEventResult {
  const spaceIdx = args.indexOf(" ");
  const url = spaceIdx === -1 ? args : args.slice(0, spaceIdx);
  const prompt = spaceIdx === -1 ? "solve each challenge" : args.slice(spaceIdx + 1).trim();
  if (!url) {
    return { action: "transform", text: "Usage: /batch scrape <url> [prompt]" };
  }

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
}

function handleIndex(args: string): InputEventResult {
  const spaceIdx = args.indexOf(" ");
  const dir = spaceIdx === -1 ? args : args.slice(0, spaceIdx);
  const prompt = spaceIdx === -1 ? "solve each challenge" : args.slice(spaceIdx + 1).trim();
  if (!dir) {
    return { action: "transform", text: "Usage: /batch index <dir> [prompt]" };
  }
  if (!fs.existsSync(dir)) {
    return { action: "transform", text: `Error: Directory not found: ${dir}` };
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
}

function handleList(): InputEventResult {
  if (!fs.existsSync(INDEX_PATH)) {
    return { action: "transform", text: "No index file found. Use /batch scrape or /batch index first." };
  }

  const content = fs.readFileSync(INDEX_PATH, "utf-8");
  const items = content.match(/## Item \d+: .+/g);
  const goalLine = content.match(/Goal: .+/);
  if (!items || items.length === 0) {
    return { action: "transform", text: "Index file exists but no items found. Regenerate." };
  }

  return {
    action: "transform",
    text: [
      `**${items.length} items indexed**`,
      goalLine?.[0] || "",
      "",
      ...items.map(l => l.replace("## ", "")),
      "",
      "Use /batch act to process them.",
    ].join("\n"),
  };
}

function handleAct(): InputEventResult {
  if (!fs.existsSync(INDEX_PATH)) {
    return { action: "transform", text: "No index file found. Use /batch scrape or /batch index first." };
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
    return { action: "transform", text: "No parseable items in the index file." };
  }

  const goalLine = content.match(/Goal: .+/)?.[0] || "";

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
}
