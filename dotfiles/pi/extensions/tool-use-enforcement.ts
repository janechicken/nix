import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", (event) => {
    return {
      systemPrompt:
        event.systemPrompt +
        "\n\n## Tool Use Required\n" +
        "You MUST use tool calls in every response. Text-only responses without tool " +
        "calls are not allowed unless the output is a short confirmation (<40 chars) or " +
        "contains code blocks (```). Research questions, analysis, and planning all " +
        "require tool calls to verify claims, read files, and gather evidence.\n",
    };
  });
}
