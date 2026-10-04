import { readFile, writeFile } from "node:fs/promises";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const BASE_URL = "https://api-gateway.merge.dev/v1/openai";
const CATALOG_URL = "https://api-gateway.merge.dev/v1/models";
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

// Merge's routing-policy id: Gateway picks the vendor/model per request
// from the key's routing policy. Not part of the /v1/models catalog.
const ROUTING_POLICY_SPEC: MergeModelSpec = {
  id: "default_routing",
  name: "Routing policy (default_routing)",
  reasoning: true,
  input: ["text", "image"],
  contextWindow: 200000,
  maxTokens: 16384,
};

// ---------------------------------------------------------------------------
// Live catalog: GET /v1/models
//
// Unlike /v1/openai/models (bare ids only), this endpoint carries per-vendor
// metadata: context_window, max_output_tokens, input/output modalities,
// supports_reasoning. It is cursor-paginated (limit + cursor + has_more).
// ---------------------------------------------------------------------------

type MergeVendorSpec = {
  context_window?: number | null;
  max_output_tokens?: number | null;
  availability_status?: string;
  capabilities?: {
    input?: string[];
    output?: string[];
    supports_reasoning?: boolean;
  };
};

type MergeCatalogEntry = {
  model?: string;
  display_name?: string;
  vendors?: Record<string, MergeVendorSpec>;
};

type MergeCatalogPage = {
  data?: MergeCatalogEntry[];
  has_more?: boolean;
  next_cursor?: string | null;
};

const CATALOG_PAGE_LIMIT = 100;
const CATALOG_MAX_PAGES = 10;

/** Fetch the full paginated /v1/models catalog. Throws on HTTP/network errors. */
async function fetchCatalog(key: string): Promise<MergeCatalogEntry[]> {
  const entries: MergeCatalogEntry[] = [];
  const seen = new Set<string>();
  let cursor: string | undefined;
  for (let page = 0; page < CATALOG_MAX_PAGES; page++) {
    const url = new URL(CATALOG_URL);
    url.searchParams.set("limit", String(CATALOG_PAGE_LIMIT));
    if (cursor) url.searchParams.set("cursor", cursor);
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${key}` },
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) {
      throw new Error(`GET /v1/models -> HTTP ${res.status}`);
    }
    const payload = (await res.json()) as MergeCatalogPage;
    for (const entry of payload.data ?? []) {
      if (entry.model && !seen.has(entry.model)) {
        seen.add(entry.model);
        entries.push(entry);
      }
    }
    if (!payload.has_more || !payload.next_cursor) break;
    cursor = payload.next_cursor;
  }
  return entries;
}

/**
 * Map a catalog entry to an omp model spec, or null when the model cannot
 * serve chat completions at all (TTS / image / video / speech endpoints
 * reject /v1/openai/chat/completions with unsupported_endpoint_for_model).
 *
 * Specs take the friendliest vendor: largest context/output windows, image
 * input if any vendor supports it, reasoning if any vendor supports it.
 */
function toModelSpec(entry: MergeCatalogEntry): MergeModelSpec | null {
  let contextWindow = 0;
  let maxTokens = 0;
  let image = false;
  let reasoning = false;
  let chatCapable = false;
  for (const vendor of Object.values(entry.vendors ?? {})) {
    const input = vendor.capabilities?.input ?? [];
    const output = vendor.capabilities?.output ?? [];
    if (input.includes("text") && output.includes("text")) {
      chatCapable = true;
    }
    if (input.includes("image")) image = true;
    if (vendor.capabilities?.supports_reasoning) reasoning = true;
    contextWindow = Math.max(contextWindow, vendor.context_window ?? 0);
    maxTokens = Math.max(maxTokens, vendor.max_output_tokens ?? 0);
  }
  if (!chatCapable) return null;
  return {
    id: entry.model as string,
    ...(entry.display_name ? { name: `${entry.display_name} (Merge)` } : {}),
    ...(reasoning ? { reasoning: true } : {}),
    ...(image ? { input: ["text", "image"] } : {}),
    ...(contextWindow > 0 ? { contextWindow } : {}),
    ...(maxTokens > 0 ? { maxTokens } : {}),
  };
}

// Last-good catalog cache: on startup with no network / bad key, the provider
// still exposes the models from the most recent successful fetch.
const CACHE_FILE = new URL("./models-cache.json", import.meta.url);

async function readCache(): Promise<MergeModelSpec[]> {
  try {
    const parsed: unknown = JSON.parse(await readFile(CACHE_FILE, "utf8"));
    return Array.isArray(parsed) ? (parsed as MergeModelSpec[]) : [];
  } catch {
    return [];
  }
}

async function writeCache(models: MergeModelSpec[]): Promise<void> {
  try {
    await writeFile(CACHE_FILE, JSON.stringify(models, null, 2));
  } catch {
    // cache write failure is non-fatal
  }
}

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

  const key = process.env[API_KEY_ENV];
  let models: MergeModelSpec[] = [];

  if (key) {
    try {
      const catalog = await fetchCatalog(key);
      models = catalog
        .map(toModelSpec)
        .filter((m): m is MergeModelSpec => m !== null);
    } catch {
      // Network/HTTP failure: fall back to the last good catalog.
      models = await readCache();
    }
    if (models.length > 0) {
      void writeCache(models);
    }
  } else {
    models = await readCache();
  }

  if (!models.some((m) => m.id === ROUTING_POLICY_SPEC.id)) {
    models.push(ROUTING_POLICY_SPEC);
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
