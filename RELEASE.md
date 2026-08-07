# Pi Black

Claude Code wire compatibility for Pi.

This unofficial release is installable as a Pi package from its Git tag. It also applies the repository's retained patch series to the immutable Pi commit recorded in `config/pi.env` and builds Pi's six supported standalone targets.

Install the package with:

```sh
pi install git:github.com/paoloanzn/pi-black@<tag>
```

Binary assets include:

- macOS arm64 and x64 archives;
- Linux arm64 and x64 archives;
- Windows arm64 and x64 archives;
- the exact `git am` patch series;
- pinned source/build metadata;
- SHA-256 checksums and generated provenance.

This project is unofficial and is not affiliated with or endorsed by Anthropic or the upstream Pi project. It contains no OAuth credentials, account identifiers, device identifiers, captures, or private system prompts. Users must provide their own credentials and are responsible for complying with applicable service terms.
