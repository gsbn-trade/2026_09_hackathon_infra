// Baked into the custom image at build time (see ../Dockerfile), replacing
// bolt.diy's own app/lib/modules/llm/registry.ts. The stock file registers
// ~20 providers; LLMManager picks the first-registered one as the default
// and the chat UI's provider dropdown lists every registered one,
// regardless of whether it's actually configured. For this hackathon
// there's exactly one real backend — LiteLLM, via the OpenAI-Like provider
// — so registering only that one provider makes it both the (only
// possible) default and the (only) dropdown entry, with no other code
// changes needed: everything downstream (DEFAULT_PROVIDER, PROVIDER_LIST,
// the cookie-restore fallback in Chat.client.tsx) derives from whatever
// this file exports.
//
// If bolt.diy ever needs a second real backend again, add its import/export
// back here — this intentionally isn't a diff against upstream's file so it
// doesn't silently go stale as upstream adds/removes providers.
import OpenAILikeProvider from './providers/openai-like';

export { OpenAILikeProvider };
