/**
 * Refuseless Provider Extension
 *
 * Registers api.refuseless.com (https://api.refuseless.com/v1) — an
 * [OI]-compatible hosted gateway for refusal-removed open weights — as a
 * provider in pi.
 *
 * Auth: reads REFUSELESS_API_KEY from the environment. The key is provisioned
 *       out of band (sops-nix session variable / shell export); it is never
 *       baked into this file or into the Nix store.
 *
 * Sources (read 2026-11-22):
 *   - https://docs.refuseless.com/introduction
 *   - https://docs.refuseless.com/api/models
 *   - https://docs.refuseless.com/api/chat-completions
 *
 * Behaviour:
 *   - The catalog (`GET /v1/models`) is public. With a key set it also lists
 *     private models, so discovery wins whenever it answers.
 *   - Discovery failure (offline, gateway error, rejected key) falls back to
 *     the bundled seed so model names and windows stay available. pi still
 *     needs a valid key to authenticate either way.
 *
 * Wire quirks carried by the provider row (not settable through
 * registerProvider): chat completions report reasoning on the
 * `reasoning_content` channel and accept the `off|low|high|max` effort scale.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const BASE_URL = "https://api.refuseless.com/v1";
const API_KEY_ENV = "REFUSELESS_API_KEY";

const DEFAULT_CONTEXT_WINDOW = 1_048_576;
const DEFAULT_MAX_TOKENS = 32_768;
const ZERO_COST = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };

/** One catalog row; `name` and `contextWindow` are only in the bundled seed. */
interface CatalogRow {
  id: string;
  name?: string;
  contextWindow?: number;
  vision?: boolean;
  pricing?: {
    input_per_m?: number;
    cached_input_per_m?: number;
    output_per_m?: number;
  };
}

interface ProviderModel {
  id: string;
  name: string;
  reasoning: boolean;
  input: ("text" | "image")[];
  cost: typeof ZERO_COST;
  contextWindow: number;
  maxTokens: number;
}

// Mirror of the live lineup (`GET /v1/models`, read 2026-11-22). The catalog
// prices rows per model and runs discounts, so seed rows stay unpriced instead
// of freezing a day's card; discovery fills in the real rates.
const SEED: CatalogRow[] = [
  {
    id: "deepseek-v4.1-flash-abliterated",
    name: "DeepSeek V4.1 Flash Abliterated",
    vision: true,
  },
  {
    id: "deepseek-v4.1-flash-abliterated-fast",
    name: "DeepSeek V4.1 Flash Abliterated Fast",
    vision: true,
  },
  {
    id: "deepseek-v4.1-flash-fast",
    name: "DeepSeek V4.1 Flash Fast",
    vision: true,
  },
  { id: "glm-5.3-abliterated", name: "GLM 5.3 Abliterated" },
  {
    id: "glm-5.3-flash-abliterated",
    name: "GLM 5.3 Flash Abliterated",
    vision: true,
  },
  { id: "kimi-k3.1-pro", name: "Kimi K3.1 Pro", vision: true },
  {
    id: "kimi-k3.1-pro-abliterated",
    name: "Kimi K3.1 Pro Abliterated",
    vision: true,
  },
  { id: "minimax-m3.1-flash", name: "MiniMax M3.1 Flash", vision: true },
  {
    id: "gemma-4-26b-storyteller",
    name: "Gemma 4 26B Storyteller",
    contextWindow: 262_144,
    vision: true,
  },
];

function toProviderModel(row: CatalogRow): ProviderModel {
  const contextWindow = row.contextWindow ?? DEFAULT_CONTEXT_WINDOW;
  const pricing = row.pricing;
  // USD per 1M tokens. Missing/zero rates stay zero, which pi reads as unpriced.
  const rate = (value: number | undefined) =>
    typeof value === "number" && Number.isFinite(value) && value > 0
      ? value
      : 0;
  return {
    id: row.id,
    name: row.name ?? row.id,
    reasoning: true,
    input: row.vision ? ["text", "image"] : ["text"],
    cost: pricing
      ? {
          input: rate(pricing.input_per_m),
          output: rate(pricing.output_per_m),
          cacheRead: rate(pricing.cached_input_per_m),
          cacheWrite: 0,
        }
      : ZERO_COST,
    contextWindow,
    maxTokens: Math.min(DEFAULT_MAX_TOKENS, Math.floor(contextWindow / 4)),
  };
}

/** GET /v1/models — public; a key widens it to the key's private models. */
async function fetchCatalog(apiKey: string | undefined): Promise<CatalogRow[]> {
  const response = await fetch(`${BASE_URL}/models`, {
    headers: apiKey ? { Authorization: `Bearer ${apiKey}` } : {},
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    throw new Error(`GET /models failed: HTTP ${response.status}`);
  }
  const payload = (await response.json()) as { data?: unknown };
  if (!Array.isArray(payload.data))
    throw new Error("GET /models returned no data array");
  return payload.data
    .filter(
      (row): row is CatalogRow =>
        !!row &&
        typeof row === "object" &&
        typeof (row as CatalogRow).id === "string",
    )
    .map((row) => ({
      ...row,
      // Catalog rows carry no display name; keep the seed's when we have one.
      name: SEED.find((seed) => seed.id === row.id)?.name,
      vision: row.vision === true,
    }));
}

export default async function (pi: ExtensionAPI) {
  const apiKey = process.env[API_KEY_ENV];
  let rows = SEED;

  if (apiKey) {
    try {
      const catalog = await fetchCatalog(apiKey);
      if (catalog.length > 0) rows = catalog;
    } catch (error) {
      console.error(
        `[refuseless-provider] catalog discovery failed, using seed models: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  } else {
    console.error(
      `[refuseless-provider] ${API_KEY_ENV} not set — registered seed models only. ` +
        `Export the key (sops-nix secret: refuseless_api_key) and /reload.`,
    );
  }

  pi.registerProvider("refuseless", {
    name: "Refuseless",
    baseUrl: BASE_URL,
    apiKey: `$${API_KEY_ENV}`,
    api: "openai-completions",
    models: rows.map(toProviderModel),
  });
}
