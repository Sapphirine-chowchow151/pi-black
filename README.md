# Pi Black

Claude Code wire compatibility for Pi.

Pi Black is an unofficial, patch-only distribution for building Pi with Anthropic Claude Pro/Max OAuth request compatibility.

The repository does not vendor Pi source. It pins an immutable commit from [`paoloanzn/pi`](https://github.com/paoloanzn/pi), applies a `git am` patch series, and delegates standalone compilation to Pi's own release builder.

## What the patch changes

For Anthropic OAuth requests only, the patch reproduces the Claude Code 2.1.224 SDK-CLI request conventions needed for subscription routing:

- exact billing and Agent SDK system-block ordering;
- the prompt-dependent `cc_version` suffix;
- the serialized-body `cch` checksum using seeded XXH64;
- per-request `x-client-request-id` values;
- Claude Code session and identity metadata.

API-key requests and non-Anthropic providers are unchanged.

## Build

Requirements, pinned inputs, and repeatability limits are in [`BUILD.md`](BUILD.md).

```sh
./scripts/verify.sh
./scripts/build-all.sh "$PWD/out"
```

The output contains all targets supported by Pi's release script:

- `darwin-arm64`
- `darwin-x64`
- `linux-arm64`
- `linux-x64`
- `windows-arm64`
- `windows-x64`

## Apply manually

```sh
git clone https://github.com/paoloanzn/pi.git pi
cd pi
git checkout --detach 7aca0d7b3e041a9e2b635e8370b2549f032932d6
git am ../pi-black/patches/*.patch
```

## Runtime configuration

Pi's normal Anthropic login stores the OAuth credential. Subscription routing additionally requires identity values belonging to the same user and installation:

```sh
export CLAUDE_CODE_DEVICE_ID='<your-private-device-id>'
export CLAUDE_CODE_ACCOUNT_UUID='<your-private-account-uuid>'
./pi
```

No real values are included here or in release artifacts. Do not publish tokens, identifiers, captures, or private Claude state.

## Releases

Pushing a `v*` tag runs `.github/workflows/release.yml`. It verifies the patch, builds all six targets, creates checksums and provenance, and publishes the assets to a GitHub Release. Pull requests and ordinary pushes run `.github/workflows/verify.yml` without provider credentials or paid API calls.

## Status and terms

This project is unofficial and is not affiliated with or endorsed by Anthropic or the upstream Pi project. Users must provide their own valid account credentials and determine whether use complies with applicable service terms. The compatibility mechanism is version-specific and must be revalidated when Claude Code or Pi changes.

Pi and the derived patch are distributed under the MIT license; see [`LICENSE`](LICENSE).
