/**
 * CheapCompute Provider Extension
 *
 * Registers cheapcompute.app (https://cheapcompute.app/api/v1) as an
 * OpenAI-compatible provider in pi.
 *
 * Auth: reads CHEAPCOMPUTE_API_KEY env var (set system-wide via sops-nix
 *       sessionVariables; secret: cheapcompute_api_key).
 *
 * Autodetection:
 *   - Fetches GET /models at startup and derives model fields from the
 *     response (handles OpenRouter-style objects: context_length,
 *     pricing.{prompt,completion}, modality — plus generic aliases).
 *   - CheapCompute's /models returns bare { id, object, owned_by }, so
 *     missing fields are inferred from the model id (family map below:
 *     reasoning support, context window, vision). API-provided fields
 *     always win over inference.
 *
 * Usage: /model cheapcompute/<model-id>
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const BASE_URL = "https://cheapcompute.app/api/v1";
const API_KEY_ENV = "CHEAPCOMPUTE_API_KEY";

// Safe defaults when neither the API nor id inference yields a value.
const DEFAULT_CONTEXT_WINDOW = 128_000;
const DEFAULT_MAX_TOKENS = 8_192;
const DEFAULT_COST = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };

interface RawModel {
  id: string;
  name?: string;
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// Id-based inference (used only when the /models response lacks the field)
// ---------------------------------------------------------------------------

interface FamilyRule {
  /** Substring matched against lowercase model id; first match wins. */
  match: string;
  contextWindow: number;
  reasoning: boolean;
  /** Whether the family accepts image input. */
  vision?: boolean;
  /** Max output tokens (default: derived from contextWindow if unset). */
  maxTokens?: number;
}

// Most specific patterns first (e.g. "gpt-4o-mini" before "gpt-4o",
// "qwen3-vl" before "qwen3").
const FAMILY_RULES: FamilyRule[] = [
  // ---- Claude (Anthropic) ----
  // 5/4.8/4.7/4.6-gen (fable, opus, sonnet) = 1M ctx / 128K out;
  // 4.5-gen (haiku/sonnet/opus 4.5) = 200K / 64K out. All reasoning + vision.
  { match: "claude-fable", contextWindow: 1_000_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "claude-opus-4-8", contextWindow: 1_000_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "claude-opus-4.8", contextWindow: 1_000_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "claude-opus-4.7", contextWindow: 1_000_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "claude-opus-4.6", contextWindow: 1_000_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "claude-sonnet-4.6", contextWindow: 1_000_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "claude-opus-5", contextWindow: 1_000_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "claude-sonnet-5", contextWindow: 1_000_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "claude", contextWindow: 200_000, reasoning: true, vision: true, maxTokens: 64_000 },

  // ---- Gemini (Google) ----
  // All 1M ctx, thinking + vision, 65,536 max output.
  { match: "gemini", contextWindow: 1_048_576, reasoning: true, vision: true, maxTokens: 65_536 },

  // ---- DeepSeek ----
  // V4 series: 1M ctx / 384K output. R1 + V3.2: 128K.
  { match: "deepseek-v4", contextWindow: 1_000_000, reasoning: true, maxTokens: 384_000 },
  { match: "deepseek-r1", contextWindow: 128_000, reasoning: true },
  { match: "deepseek", contextWindow: 128_000, reasoning: true },

  // ---- GPT-5.x (OpenAI) ----
  // 5.4/5.5/5.6 = 1.05M ctx / 128K out; 5.4-mini/nano = 400K; gpt-5-mini = 128K.
  { match: "gpt-5-mini", contextWindow: 128_000, reasoning: true, vision: true, maxTokens: 16_384 },
  { match: "gpt-5.4-mini", contextWindow: 400_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "gpt-5.4-nano", contextWindow: 400_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "gpt-5.6", contextWindow: 1_050_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "gpt-5", contextWindow: 1_050_000, reasoning: true, vision: true, maxTokens: 128_000 },

  // ---- GPT-4o (OpenAI) ----
  // Hybrid, no extended thinking, 16K max output.
  { match: "gpt-4o-mini", contextWindow: 128_000, reasoning: false, vision: true, maxTokens: 16_384 },
  { match: "gpt-4o", contextWindow: 128_000, reasoning: false, vision: true, maxTokens: 16_384 },

  // ---- GPT-OSS (OpenAI open-weight) ----
  // 131K ctx, CoT reasoning, text-only.
  { match: "gpt-oss", contextWindow: 131_072, reasoning: true },

  // ---- Kimi (Moonshot) ----
  // K3 = 1M ctx + native vision; K2.5+ = 256K; base K2 = 128K text-only.
  { match: "kimi-k3", contextWindow: 1_000_000, reasoning: true, vision: true, maxTokens: 131_072 },
  { match: "kimi-k2.7", contextWindow: 256_000, reasoning: true, vision: true },
  { match: "kimi-k2.6", contextWindow: 256_000, reasoning: true, vision: true },
  { match: "kimi-k2.5", contextWindow: 256_000, reasoning: true, vision: true },
  { match: "kimi-k2-thinking", contextWindow: 256_000, reasoning: true, vision: true },
  { match: "kimi", contextWindow: 128_000, reasoning: true },

  // ---- GLM (Zhipu/Z.AI) ----
  // 4.5 = 128K / 96K out; 4.6+ = 200K / 128K out; 5.2 = 1M. 5v-turbo is the only VLM.
  { match: "glm-5.2", contextWindow: 1_000_000, reasoning: true, maxTokens: 128_000 },
  { match: "glm-5v", contextWindow: 200_000, reasoning: true, vision: true, maxTokens: 128_000 },
  { match: "glm-5", contextWindow: 200_000, reasoning: true, maxTokens: 128_000 },
  { match: "glm-4.7", contextWindow: 200_000, reasoning: true, maxTokens: 128_000 },
  { match: "glm-4.6", contextWindow: 200_000, reasoning: true, maxTokens: 128_000 },
  { match: "glm-4.5", contextWindow: 128_000, reasoning: true, maxTokens: 96_000 },

  // ---- Grok (xAI) ----
  // 4.1-fast = 2M; 4.3/4.20 = 1M; 4.5 = 500K; build-0.1 = 256K. All reasoning + vision.
  { match: "grok-4.1-fast", contextWindow: 2_000_000, reasoning: true, vision: true },
  { match: "grok-4.20", contextWindow: 1_000_000, reasoning: true, vision: true },
  { match: "grok-4.3", contextWindow: 1_000_000, reasoning: true, vision: true },
  { match: "grok-4.5", contextWindow: 500_000, reasoning: true, vision: true },
  { match: "grok-build", contextWindow: 256_000, reasoning: true, vision: true },
  { match: "grok", contextWindow: 1_000_000, reasoning: true, vision: true },

  // ---- Qwen (Alibaba) ----
  // 3.7-max/plus, 3.5-plus/flash, 3-coder = 1M; vl = 256K; dense 3.x = 128K.
  { match: "qwen-3-7", contextWindow: 1_000_000, reasoning: true },
  { match: "qwen3-vl", contextWindow: 256_000, reasoning: true, vision: true },
  { match: "qwen3.5-plus", contextWindow: 1_000_000, reasoning: true },
  { match: "qwen3.5-flash", contextWindow: 1_000_000, reasoning: true },
  { match: "qwen3-coder", contextWindow: 1_000_000, reasoning: true },
  { match: "qwen3.6-plus", contextWindow: 1_000_000, reasoning: true },
  { match: "qwen3", contextWindow: 128_000, reasoning: true },

  // ---- MiniMax ----
  // M3 = 1M + vision; M2.x = 200K text-only, 128K max output.
  { match: "minimax-m3", contextWindow: 1_000_000, reasoning: true, vision: true },
  { match: "minimax-m2.7", contextWindow: 204_800, reasoning: true, maxTokens: 128_000 },
  { match: "minimax", contextWindow: 200_000, reasoning: true, maxTokens: 128_000 },

  // ---- NVIDIA Nemotron ----
  // 3.x = up to 1M (default 256K), configurable thinking, text-only.
  { match: "nvidia-nemotron", contextWindow: 256_000, reasoning: true, maxTokens: 128_000 },

  // ---- Aion ----
  // 2.0 (DeepSeek V3.2 fine-tune): 131K, thinking mode, text-only.
  { match: "aion", contextWindow: 131_072, reasoning: true, maxTokens: 32_768 },

  // ---- Gemma (Google) ----
  // 3.x = 128K instruct, no CoT; 4.x = 256K with <|think|> mode. Both vision.
  { match: "gemma-4", contextWindow: 256_000, reasoning: true, vision: true },
  { match: "gemma-3", contextWindow: 128_000, reasoning: false, vision: true },

  // ---- Llama / Hermes ----
  // Instruct-tuned, no CoT, text-only.
  { match: "hermes", contextWindow: 128_000, reasoning: false },
  { match: "llama", contextWindow: 128_000, reasoning: false },

  // ---- Mistral ----
  // small-3.2 = 128K no-CoT but vision; small-4 = 256K reasoning + vision;
  // large = 128K no-CoT, text-only.
  { match: "mistral-small-3.2", contextWindow: 128_000, reasoning: false, vision: true },
  { match: "mistral-small-4", contextWindow: 256_000, reasoning: true, vision: true },
  { match: "mistral-large", contextWindow: 128_000, reasoning: false },
  { match: "mistral", contextWindow: 128_000, reasoning: false },

  // ---- Mercury / Venice ----
  // mercury-2 = reasoning diffusion LLM, text-only; venice = decensored Mistral instruct + vision.
  { match: "mercury", contextWindow: 128_000, reasoning: true, maxTokens: 128_000 },
  { match: "venice", contextWindow: 128_000, reasoning: false, vision: true },
];

function inferFamily(model: RawModel): FamilyRule | undefined {
  const id = model.id.toLowerCase();
  return FAMILY_RULES.find((rule) => id.includes(rule.match));
}

// ---------------------------------------------------------------------------
// API-field extraction (OpenRouter-style + generic aliases)
// ---------------------------------------------------------------------------

/** First numeric-ish value among candidate keys, else fallback. */
function pickNum(model: RawModel, keys: string[], fallback: number): number {
  for (const key of keys) {
    const value = model[key];
    if (typeof value === "number" && Number.isFinite(value) && value > 0) return value;
    if (typeof value === "string") {
      const parsed = Number.parseFloat(value);
      if (Number.isFinite(parsed) && parsed > 0) return parsed;
    }
  }
  return fallback;
}

function pickBool(model: RawModel, keys: string[], fallback: boolean): boolean {
  for (const key of keys) {
    const value = model[key];
    if (typeof value === "boolean") return value;
  }
  return fallback;
}

/** Context window from API response, or undefined if absent. */
function apiContextWindow(model: RawModel): number | undefined {
  const value = pickNum(
    model,
    ["context_length", "context_window", "contextWindow", "max_context", "ctx_length"],
    0,
  );
  return value > 0 ? Math.floor(value) : undefined;
}

/** Max output tokens from API response, or undefined if absent. */
function apiMaxTokens(model: RawModel): number | undefined {
  const value = pickNum(model, ["max_tokens", "max_completion_tokens", "max_output_tokens", "output_tokens"], 0);
  return value > 0 ? Math.floor(value) : undefined;
}

/** Reasoning flag from API response, or undefined if absent. */
function apiReasoning(model: RawModel): boolean | undefined {
  for (const key of ["reasoning", "supports_reasoning", "reasoning_capable", "thinking", "supports_thinking"]) {
    const value = model[key];
    if (typeof value === "boolean") return value;
  }
  return undefined;
}

/** Input modalities from API response; undefined when uninformative. */
function apiInput(model: RawModel): ("text" | "image")[] | undefined {
  const modality = model.modality;
  if (modality && typeof modality === "object") {
    const m = modality as Record<string, unknown>;
    const image =
      m.image === true || (Array.isArray(m.input) && (m.input as unknown[]).includes("image"));
    return image ? ["text", "image"] : ["text"];
  }
  const modalities = model.modalities ?? model.input_modalities;
  if (Array.isArray(modalities)) {
    return (modalities as unknown[]).includes("image") ? ["text", "image"] : ["text"];
  }
  if (model.image === true || pickBool(model, ["supports_vision", "vision"], false)) {
    return ["text", "image"];
  }
  return undefined;
}

/** Cost per 1M tokens from API response (OpenRouter pricing or flat keys). */
function apiCost(model: RawModel): typeof DEFAULT_COST | undefined {
  const pricing = model.pricing;
  if (pricing && typeof pricing === "object") {
    const p = pricing as Record<string, unknown>;
    const read = (key: string) => {
      const value = p[key];
      if (typeof value === "number" && Number.isFinite(value)) return Math.max(0, value);
      if (typeof value === "string") {
        const parsed = Number.parseFloat(value);
        return Number.isFinite(parsed) ? Math.max(0, parsed) : 0;
      }
      return 0;
    };
    return {
      input: read("prompt"),
      output: read("completion"),
      cacheRead: read("cache_read") || read("read_cache"),
      cacheWrite: read("cache_write") || read("write_cache"),
    };
  }
  const input = pickNum(model, ["input_cost", "input_price", "price_in", "cost_per_million_input"], 0);
  const output = pickNum(model, ["output_cost", "output_price", "price_out", "cost_per_million_output"], 0);
  if (input > 0 || output > 0) {
    return {
      input,
      output,
      cacheRead: pickNum(model, ["cache_read_cost", "cache_read_price"], 0),
      cacheWrite: pickNum(model, ["cache_write_cost", "cache_write_price"], 0),
    };
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// Model assembly
// ---------------------------------------------------------------------------

function toProviderModel(model: RawModel) {
  const id = model.id;
  const name = typeof model.name === "string" ? model.name : id;
  const family = inferFamily(model);
  const contextWindow = apiContextWindow(model) ?? family?.contextWindow ?? DEFAULT_CONTEXT_WINDOW;
  const apiMax = apiMaxTokens(model);
  const maxTokens =
    apiMax ??
    family?.maxTokens ??
    Math.min(DEFAULT_MAX_TOKENS, Math.floor(contextWindow / 4));
  const reasoning = apiReasoning(model) ?? family?.reasoning ?? false;
  const input = apiInput(model) ?? (family?.vision ? ["text", "image"] : ["text"]);
  const cost = apiCost(model) ?? DEFAULT_COST;

  return { id, name, reasoning, input, cost, contextWindow, maxTokens };
}

async function fetchModels(apiKey: string): Promise<RawModel[]> {
  const response = await fetch(`${BASE_URL}/models`, {
    headers: { Authorization: `Bearer ${apiKey}` },
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) {
    throw new Error(`GET /models failed: HTTP ${response.status} ${await response.text().catch(() => "")}`);
  }
  const payload = (await response.json()) as { data?: unknown };
  if (!Array.isArray(payload.data)) throw new Error("GET /models returned no data array");
  return payload.data.filter((m): m is RawModel => !!m && typeof m === "object" && typeof (m as RawModel).id === "string");
}

export default async function (pi: ExtensionAPI) {
  let models: RawModel[] = [];

  if (process.env[API_KEY_ENV]) {
    try {
      models = await fetchModels(process.env[API_KEY_ENV]);
    } catch (error) {
      console.error(`[cheapcompute-provider] model discovery failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  } else {
    console.error(
      `[cheapcompute-provider] ${API_KEY_ENV} not set — provider registered without models. ` +
        `Set the env var (sops secret: cheapcompute_api_key) and /reload.`,
    );
  }

  pi.registerProvider("cheapcompute", {
    name: "CheapCompute",
    baseUrl: BASE_URL,
    apiKey: `$${API_KEY_ENV}`,
    api: "openai-completions",
    models: models.map(toProviderModel),
  });
}
