import { builtinProviders } from "@earendil-works/pi-ai/providers/all";
import { type ExtensionAPI, VERSION } from "@earendil-works/pi-coding-agent";
import { wrapAnthropicProvider } from "../src/anthropic-provider.ts";
import {
	discoverClaudeCodeIdentity,
	SUPPORTED_PI_VERSION,
} from "../src/claude-code-protocol.ts";

export default function piBlack(pi: ExtensionAPI): void {
	if (VERSION !== SUPPORTED_PI_VERSION) {
		throw new Error(
			`Pi Black supports Pi ${SUPPORTED_PI_VERSION}; running Pi is ${VERSION}`,
		);
	}
	const anthropic = builtinProviders().find(
		(provider) => provider.id === "anthropic",
	);
	if (!anthropic)
		throw new Error("Pi Black could not load Pi's built-in Anthropic provider");
	pi.registerProvider(
		wrapAnthropicProvider(anthropic, discoverClaudeCodeIdentity()),
	);
}
