// Baked into the custom image at build time (see ../Dockerfile), replacing
// bolt.diy's own app/lib/modules/llm/providers/openai-like.ts.
//
// The stock getDynamicModels() calls `${baseUrl}/models` — an OpenAI-style
// bare model list (`{id: "..."}`, no token-limit fields) — and then
// hardcodes `maxTokenAllowed: 8000` for literally every model regardless of
// what it can actually do. That value both mislabels every model in the UI
// and (via stream-text.ts's getCompletionTokenLimit(), which prefers
// modelDetails.maxCompletionTokens when set) determines the real per-call
// `max_tokens` sent to the API — so every response over ~8K tokens gets
// chopped into slow sequential "continue" round-trips, and can leave files
// unwritten if bolt.diy runs out of continuation attempts mid-plan.
//
// Fix: try LiteLLM's richer `/model/info` first, which reports each
// model's real max_tokens/max_output_tokens (set explicitly in
// litellm-config.yaml's model_info blocks for exactly this reason). Only
// fall back to the original `/models`-based 8000-token behavior if
// `/model/info` isn't available at all — keeps this provider working
// generically against any plain OpenAI-compatible backend, not just
// LiteLLM.
import { BaseProvider, getOpenAILikeModel } from '~/lib/modules/llm/base-provider';
import type { ModelInfo } from '~/lib/modules/llm/types';
import type { IProviderSetting } from '~/types/model';
import type { LanguageModelV1 } from 'ai';
import { logger } from '~/utils/logger';

interface OpenAIModelsResponse {
  data: Array<{ id: string }>;
}

interface LiteLLMModelInfoResponse {
  data: Array<{
    model_name: string;
    model_info?: {
      max_tokens?: number | null;
      max_output_tokens?: number | null;
    };
  }>;
}

const FALLBACK_MAX_TOKEN_ALLOWED = 8000;

export default class OpenAILikeProvider extends BaseProvider {
  name = 'OpenAILike';
  getApiKeyLink = undefined;

  config = {
    baseUrlKey: 'OPENAI_LIKE_API_BASE_URL',
    apiTokenKey: 'OPENAI_LIKE_API_KEY',
    modelsKey: 'OPENAI_LIKE_API_MODELS',
  };

  staticModels: ModelInfo[] = [];

  async getDynamicModels(
    apiKeys?: Record<string, string>,
    settings?: IProviderSetting,
    serverEnv: Record<string, string> = {},
  ): Promise<ModelInfo[]> {
    const { baseUrl, apiKey } = this.getProviderBaseUrlAndKey({
      apiKeys,
      providerSettings: settings,
      serverEnv,
      defaultBaseUrlKey: 'OPENAI_LIKE_API_BASE_URL',
      defaultApiTokenKey: 'OPENAI_LIKE_API_KEY',
    });

    if (!baseUrl || !apiKey) {
      return [];
    }

    // Try LiteLLM's richer endpoint first — real per-model limits.
    try {
      const response = await fetch(`${baseUrl}/model/info`, {
        headers: {
          Authorization: `Bearer ${apiKey}`,
        },
        signal: this.createTimeoutSignal(),
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const res = (await response.json()) as LiteLLMModelInfoResponse;

      if (!Array.isArray(res.data)) {
        throw new Error('Unexpected /model/info response shape');
      }

      return res.data.map((model) => {
        const limit =
          model.model_info?.max_output_tokens || model.model_info?.max_tokens || FALLBACK_MAX_TOKEN_ALLOWED;

        return {
          name: model.model_name,
          label: model.model_name,
          provider: this.name,
          maxTokenAllowed: limit,
          maxCompletionTokens: limit,
        };
      });
    } catch (modelInfoError) {
      logger.info(`${this.name}: /model/info unavailable, falling back to /models`, modelInfoError);
    }

    // Fall back to the plain OpenAI-style model list (no per-model limits
    // available from this endpoint shape) — keeps this provider working
    // against any generic OpenAI-compatible backend, not just LiteLLM.
    try {
      const response = await fetch(`${baseUrl}/models`, {
        headers: {
          Authorization: `Bearer ${apiKey}`,
        },
        signal: this.createTimeoutSignal(),
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const res = (await response.json()) as OpenAIModelsResponse;

      return res.data.map((model) => ({
        name: model.id,
        label: model.id,
        provider: this.name,
        maxTokenAllowed: FALLBACK_MAX_TOKEN_ALLOWED,
      }));
    } catch (error) {
      logger.info(`${this.name}: Could not fetch /models endpoint, checking fallback env`, error);

      // Fallback to OPENAI_LIKE_API_MODELS if available
      // eslint-disable-next-line dot-notation
      const modelsEnv = serverEnv['OPENAI_LIKE_API_MODELS'] || settings?.OPENAI_LIKE_API_MODELS;

      if (modelsEnv) {
        logger.info(`${this.name}: Using OPENAI_LIKE_API_MODELS fallback`);

        return this._parseModelsFromEnv(modelsEnv);
      }

      return [];
    }
  }

  /**
   * Parse OPENAI_LIKE_API_MODELS environment variable
   * Format: path/to/model1:limit;path/to/model2:limit;path/to/model3:limit
   */
  private _parseModelsFromEnv(modelsEnv: string): ModelInfo[] {
    if (!modelsEnv) {
      return [];
    }

    try {
      const models: ModelInfo[] = [];
      const modelEntries = modelsEnv.split(';');

      for (const entry of modelEntries) {
        const trimmedEntry = entry.trim();

        if (!trimmedEntry) {
          continue;
        }

        const [modelPath, limitStr] = trimmedEntry.split(':');

        if (!modelPath) {
          continue;
        }

        const limit = limitStr ? parseInt(limitStr.trim(), 10) : 8000;
        const modelName = modelPath.trim();

        // Generate a readable label from the model path
        const label = this._generateModelLabel(modelName);

        models.push({
          name: modelName,
          label,
          provider: this.name,
          maxTokenAllowed: limit,
        });
      }

      logger.info(`${this.name}: Parsed ${models.length} models from env`);

      return models;
    } catch (error) {
      logger.error(`${this.name}: Error parsing OPENAI_LIKE_API_MODELS:`, error);
      return [];
    }
  }

  /**
   * Generate a readable label from model path
   */
  private _generateModelLabel(modelPath: string): string {
    // Extract the last part of the path and clean it up
    const parts = modelPath.split('/');
    const lastPart = parts[parts.length - 1];

    // Remove common prefixes and clean up the name
    let label = lastPart
      .replace(/^accounts\//, '')
      .replace(/^fireworks\/models\//, '')
      .replace(/^models\//, '')
      // Capitalize first letter of each word
      .replace(/\b\w/g, (l) => l.toUpperCase())
      // Replace spaces with hyphens for a cleaner look
      .replace(/\s+/g, '-');

    // Add provider suffix if not already present
    if (!label.includes('Fireworks') && !label.includes('OpenAI')) {
      label += ' (OpenAI Compatible)';
    }

    return label;
  }

  getModelInstance(options: {
    model: string;
    serverEnv: Env;
    apiKeys?: Record<string, string>;
    providerSettings?: Record<string, IProviderSetting>;
  }): LanguageModelV1 {
    const { model, serverEnv, apiKeys, providerSettings } = options;
    const envRecord = this.convertEnvToRecord(serverEnv);

    const { baseUrl, apiKey } = this.getProviderBaseUrlAndKey({
      apiKeys,
      providerSettings: providerSettings?.[this.name],
      serverEnv: envRecord,
      defaultBaseUrlKey: 'OPENAI_LIKE_API_BASE_URL',
      defaultApiTokenKey: 'OPENAI_LIKE_API_KEY',
    });

    if (!baseUrl || !apiKey) {
      throw new Error(`Missing configuration for ${this.name} provider`);
    }

    return getOpenAILikeModel(baseUrl, apiKey, model);
  }
}
