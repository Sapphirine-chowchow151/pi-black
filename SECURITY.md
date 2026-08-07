# Security

## Secrets

Do not commit or attach any of the following:

- Anthropic OAuth access or refresh tokens;
- `CLAUDE_CODE_DEVICE_ID` values;
- `CLAUDE_CODE_ACCOUNT_UUID` values;
- intercepted request captures;
- extracted private prompts or local Claude state.

The package reads matching identity values from Claude Code's local state in memory when available. It does not copy, log, or persist them. The retained patch can also read explicit runtime environment values. CI never reads local Claude state, performs a live provider request, or requires provider secrets.

## Release verification

Every release contains `SHA256SUMS`. Verify an extracted download before use:

```sh
sha256sum -c SHA256SUMS
```

On macOS, use `shasum -a 256` if GNU `sha256sum` is unavailable. Release binaries are produced by Bun and are not Apple-notarized unless release notes explicitly state otherwise.

## Reporting

Use a private GitHub security advisory for vulnerabilities that could expose credentials or identifiers. Do not include live credentials or captures in reports.
