import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", (event) => {
    return {
      systemPrompt:
        event.systemPrompt +
        "\n\n## Execution Discipline\n\n" +
        "You MUST use tool calls to make progress in every response. " +
        "Never end a turn with plans, intentions, or descriptions of what you will do " +
        "next — execute immediately.\n\n" +
        "### Before every action, confirm:\n" +
        "1. Do I have the file? Read it first.\n" +
        "2. Is the tool installed? Check with `which`.\n" +
        "3. Is the directory right? Verify paths.\n" +
        "4. Are there side effects? Confirm scope.\n\n" +
        "### After every action, verify:\n" +
        "- File written? Stat it. URL called? Check it. Test ran? Check exit code.\n" +
        "- Never trust a subagent's self-report — confirm independently.\n\n" +
        "### If a tool fails:\n" +
        "- Retry with a different approach before giving up.\n" +
        "- Try alternative queries, different tools, different angles.\n" +
        "- After 3 consecutive failures, explain what you tried and ask for guidance.\n\n" +
        "### Keep going:\n" +
        "- Do not stop with \"Here's what I'd do next\" — do it.\n" +
        "- Keep calling tools until the task is complete and verified.\n",
    };
  });
}
