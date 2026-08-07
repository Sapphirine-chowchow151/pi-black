import type {
	Api,
	ApiStreamOptions,
	Context,
	Model,
	Provider,
	SimpleStreamOptions,
} from "@earendil-works/pi-ai";
import {
	type ClaudeCodeIdentity,
	discoverClaudeCodeIdentity,
	isAnthropicOAuthToken,
	mergeClaudeCodeOptions,
} from "./claude-code-protocol.ts";

export function wrapAnthropicProvider(
	provider: Provider,
	identity:
		| ClaudeCodeIdentity
		| undefined
		| Promise<ClaudeCodeIdentity | undefined> = discoverClaudeCodeIdentity(),
): Provider {
	if (provider.id !== "anthropic")
		throw new Error(`Pi Black cannot wrap provider "${provider.id}"`);

	return {
		...provider,
		stream<T extends Api>(
			model: Model<T>,
			context: Context,
			options?: ApiStreamOptions<T>,
		) {
			if (!options || !isAnthropicOAuthToken(options.apiKey))
				return provider.stream(model, context, options);
			const transformed = mergeClaudeCodeOptions(options, context, identity);
			return provider.stream(model, context, transformed);
		},
		streamSimple(
			model: Model<Api>,
			context: Context,
			options?: SimpleStreamOptions,
		) {
			if (!options || !isAnthropicOAuthToken(options.apiKey))
				return provider.streamSimple(model, context, options);
			return provider.streamSimple(
				model,
				context,
				mergeClaudeCodeOptions(options, context, identity),
			);
		},
	};
}
