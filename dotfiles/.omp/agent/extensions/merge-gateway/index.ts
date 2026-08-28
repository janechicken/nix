import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const BASE_URL = "https://api-gateway.merge.dev/v1/openai";
const API_KEY_ENV = "MERGE_GATEWAY_API_KEY";
const MERGE_HOST = "api-gateway.merge.dev";

type MergeModelSpec = {
  id: string;
  name?: string;
  reasoning?: boolean;
  input?: string[];
  contextWindow?: number;
  maxTokens?: number;
};

// Curated flagships with real specs. Merge's /v1/openai/models endpoint only
// exposes bare ids (no context/vision metadata), so anything not listed here
// uses omp's defaults (128K context / 16K output / text-only).
const CURATED: MergeModelSpec[] = [
  {
    id: "anthropic/claude-opus-4.6",
    name: "Claude Opus 4.6 (Merge)",
    reasoning: true,
    input: ["text", "image"],
    contextWindow: 1000000,
    maxTokens: 64000,
  },
  {
    id: "anthropic/claude-sonnet-4-6",
    name: "Claude Sonnet 4.6 (Merge)",
    reasoning: true,
    input: ["text", "image"],
    contextWindow: 1000000,
    maxTokens: 64000,
  },
  {
    id: "openai/gpt-5.5",
    name: "GPT-5.5 (Merge)",
    reasoning: true,
    input: ["text", "image"],
    contextWindow: 400000,
    maxTokens: 64000,
  },
  {
    id: "google/gemini-3.6-flash",
    name: "Gemini 3.6 Flash (Merge)",
    reasoning: true,
    input: ["text", "image"],
    contextWindow: 1048576,
    maxTokens: 65536,
  },
  {
    id: "google/gemini-3.5-flash",
    name: "Gemini 3.5 Flash (Merge)",
    reasoning: true,
    input: ["text", "image"],
    contextWindow: 1048576,
    maxTokens: 65536,
  },
  {
    id: "deepseek/deepseek-v4-flash",
    name: "DeepSeek V4 Flash (Merge)",
    reasoning: true,
    input: ["text"],
    contextWindow: 1000000,
    maxTokens: 16384,
  },
  {
    // z.ai GLM-5.3 Flash: 1M context, 128K output (z.ai blog + HF config),
    // reasoning model, multimodal input.
    id: "zai/glm-5.3-flash",
    name: "GLM-5.3 Flash (Merge)",
    reasoning: true,
    input: ["text", "image"],
    contextWindow: 1048576,
    maxTokens: 131072,
  },
  {
    // Merge's routing-policy id: Gateway picks the vendor/model per request
    // from the key's routing policy. Remove if you don't use policies.
    id: "default_routing",
    name: "Routing policy (default_routing)",
    reasoning: true,
    input: ["text", "image"],
    contextWindow: 200000,
    maxTokens: 16384,
  },
];

// ---------------------------------------------------------------------------
// Thinking-stream repair
//
// Merge Gateway streams reasoning in a non-standard SSE field:
//   choices[0].delta.thinking (+ thinking_signature)
// omp's openai-completions decoder only recognizes
//   delta.reasoning_content | delta.reasoning | delta.reasoning_text
// so Merge thinking is silently dropped. There is no compat flag for this and
// extensions cannot register stream handlers, but omp resolves its HTTP fetch
// from globalThis.fetch at request time — so we wrap it and rename the field
// in flight, scoped strictly to Merge chat-completions responses.
// ---------------------------------------------------------------------------

/** Parse one SSE data line; rename delta.thinking → delta.reasoning_content. */
function rewriteSseDataLine(line: string): string {
  if (!line.startsWith("data:")) return line;
  const payload = line.slice(5).trimStart();
  if (!payload || payload === "[DONE]") return line;

  let parsed: unknown;
  try {
    parsed = JSON.parse(payload);
  } catch {
    return line; // split/multi-line JSON frames pass through untouched
  }
  if (!parsed || typeof parsed !== "object") return line;
  const obj = parsed as Record<string, unknown>;
  if (!Array.isArray(obj.choices) || obj.choices.length === 0) return line;
  const choice = obj.choices[0];
  if (!choice || typeof choice !== "object" || !("delta" in choice)) return line;
  const choiceRecord = choice as Record<string, unknown>;
  if (!choiceRecord.delta || typeof choiceRecord.delta !== "object") {
    return line;
  }
  const delta = choiceRecord.delta as Record<string, unknown>;
  if (typeof delta.thinking !== "string" || delta.thinking.length === 0) {
    return line;
  }
  if (delta.reasoning_content === undefined) {
    delta.reasoning_content = delta.thinking;
  }
  delete delta.thinking;
  return "data: " + JSON.stringify(obj);
}

function createSseRewriteStream(): TransformStream<Uint8Array, Uint8Array> {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";
  return new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      buffer += decoder.decode(chunk, { stream: true });
      let idx: number;
      while ((idx = buffer.indexOf("\n")) !== -1) {
        let line = buffer.slice(0, idx);
        buffer = buffer.slice(idx + 1);
        let cr = false;
        if (line.endsWith("\r")) {
          line = line.slice(0, -1);
          cr = true;
        }
        const out = rewriteSseDataLine(line);
        controller.enqueue(encoder.encode(out + (cr ? "\r\n" : "\n")));
      }
    },
    flush(controller) {
      const rest = buffer + decoder.decode();
      if (rest.length > 0) {
        controller.enqueue(encoder.encode(rewriteSseDataLine(rest)));
      }
    },
  });
}

/** Rewrite non-streaming JSON bodies (message.thinking → reasoning_content). */
async function rewriteJsonResponse(res: Response): Promise<Response> {
  const headers = new Headers(res.headers);
  headers.delete("content-length");
  const text = await res.text();
  try {
    const parsed: unknown = JSON.parse(text);
    let changed = false;
    if (parsed && typeof parsed === "object" && Array.isArray(parsed.choices)) {
      for (const choice of parsed.choices) {
        if (!choice || typeof choice !== "object" || !("message" in choice)) {
          continue;
        }
        const message = (choice as Record<string, unknown>).message;
        if (!message || typeof message !== "object") continue;
        const record = message as Record<string, unknown>;
        if (
          typeof record.thinking === "string" &&
          record.thinking.length > 0
        ) {
          if (record.reasoning_content === undefined) {
            record.reasoning_content = record.thinking;
          }
          delete record.thinking;
          changed = true;
        }
      }
    }
    if (changed) {
      return new Response(JSON.stringify(parsed), {
        status: res.status,
        statusText: res.statusText,
        headers,
      });
    }
  } catch {
    // fall through: return the original body
  }
  return new Response(text, {
    status: res.status,
    statusText: res.statusText,
    headers,
  });
}

const FETCH_WRAP_KEY = Symbol.for("merge-gateway.fetch-rewrite");

/** Wrap globalThis.fetch once; idempotent across extension reloads. */
function installThinkingFieldRewrite(): void {
  const scope = globalThis as { fetch?: typeof fetch } & Record<symbol, unknown>;
  if (typeof scope.fetch !== "function" || scope[FETCH_WRAP_KEY] === true) {
    return;
  }
  const originalFetch = scope.fetch.bind(globalThis);
  scope[FETCH_WRAP_KEY] = true;

  scope.fetch = async (
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> => {
    const res = await originalFetch(input, init);
    try {
      const url =
        typeof input === "string"
          ? input
          : input instanceof URL
            ? input.href
            : (input as Request).url ?? "";
      const method = (
        init?.method ?? (input as Request).method ?? "GET"
      ).toUpperCase();
      if (
        !url.includes(MERGE_HOST) ||
        method !== "POST" ||
        !url.includes("/chat/completions")
      ) {
        return res;
      }
      const contentType = res.headers?.get("content-type") ?? "";
      if (contentType.includes("text/event-stream") && res.body) {
        const headers = new Headers(res.headers);
        headers.delete("content-length");
        return new Response(res.body.pipeThrough(createSseRewriteStream()), {
          status: res.status,
          statusText: res.statusText,
          headers,
        });
      }
      if (contentType.includes("application/json")) {
        return await rewriteJsonResponse(res);
      }
      return res;
    } catch {
      return res; // a rewrite failure must never break the request
    }
  };
}

export default async function mergeGatewayExtension(pi: ExtensionAPI) {
  pi.setLabel("Merge Gateway provider");
  installThinkingFieldRewrite();

  const models: MergeModelSpec[] = [...CURATED];
  const key = process.env[API_KEY_ENV];

  if (key) {
    try {
      const res = await fetch(`${BASE_URL}/models`, {
        headers: { Authorization: `Bearer ${key}` },
        signal: AbortSignal.timeout(10_000),
      });
      if (res.ok) {
        const payload = (await res.json()) as { data?: { id?: string }[] };
        const seen = new Set(models.map((m) => m.id));
        for (const entry of payload.data ?? []) {
          if (!entry.id || seen.has(entry.id)) continue;
          models.push({ id: entry.id });
          seen.add(entry.id);
        }
      }
    } catch {
      // Catalog fetch failed (offline / bad key): curated list still loads.
    }
  }

  pi.registerProvider("merge-gateway", {
    baseUrl: BASE_URL,
    api: "openai-completions",
    // Resolved as an env var name first, then a literal (omp convention).
    // Set via MERGE_GATEWAY_API_KEY in ~/.omp/agent/.env.
    apiKey: API_KEY_ENV,
    // Merge Gateway forwards reasoning_effort to the upstream vendor, and
    // some vendors reject it. Merge's own pi integration docs recommend
    // disabling it (safe default). Thinking still streams by default and is
    // surfaced via the fetch rewrite above.
    compat: {
      supportsReasoningEffort: false,
    },
    models,
  });
}