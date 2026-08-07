#!/bin/sh

set -eu

REPOSITORY="paoloanzn/pi-black"
RELEASE="${PI_BLACK_RELEASE:-latest}"
INSTALL_DIR="${PI_BLACK_INSTALL_DIR:-$HOME/.local/bin}"
COMMAND_PATH="$INSTALL_DIR/pi-black"
RUNTIME_PATH="$INSTALL_DIR/pi-black-runtime"
tmp_dir=""
staged_runtime=""
staged_launcher=""
backup_runtime=""
path_action="already"
path_profile=""

step() {
  printf '==> %s\n' "$1"
}

usage() {
  cat <<'EOF'
Usage: install.sh [--release TAG]

Install the latest standalone Pi Black release for this computer.

Options:
  --release TAG  Install a specific release tag.
  -h, --help     Show this help.

Environment:
  PI_BLACK_RELEASE       Release tag to install (default: latest).
  PI_BLACK_INSTALL_DIR   Destination directory (default: ~/.local/bin).
  PI_BLACK_RELEASES_URL  Override the release-asset base URL.
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --release)
        if [ "$#" -lt 2 ]; then
          echo "--release requires a tag." >&2
          exit 1
        fi
        RELEASE="$2"
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required to install Pi Black." >&2
    exit 1
  fi
}

download_file() {
  url="$1"
  output="$2"
  progress="${3:-quiet}"

  if command -v curl >/dev/null 2>&1; then
    if [ "$progress" = "progress" ] && [ -t 2 ]; then
      curl -fL --retry 3 --progress-bar "$url" -o "$output"
    else
      curl -fsSL --retry 3 "$url" -o "$output"
    fi
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    if [ "$progress" = "progress" ] && [ -t 2 ]; then
      wget -O "$output" "$url"
    else
      wget -q -O "$output" "$url"
    fi
    return
  fi

  echo "curl or wget is required to install Pi Black." >&2
  exit 1
}

file_sha256() {
  path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" | sed 's/^.*= //'
    return
  fi

  echo "sha256sum, shasum, or openssl is required to verify Pi Black." >&2
  exit 1
}

manifest_digest() {
  manifest="$1"
  filename="$2"
  awk -v filename="$filename" '
    length($1) == 64 && $1 !~ /[^0-9a-fA-F]/ && ($2 == filename || $2 == "*" filename) {
      print tolower($1)
      exit
    }
  ' "$manifest"
}

pick_profile() {
  case "$os:${SHELL:-}" in
    darwin:*/zsh) printf '%s\n' "$HOME/.zprofile" ;;
    darwin:*/bash) printf '%s\n' "$HOME/.bash_profile" ;;
    linux:*/zsh) printf '%s\n' "$HOME/.zshrc" ;;
    linux:*/bash) printf '%s\n' "$HOME/.bashrc" ;;
    *) printf '%s\n' "$HOME/.profile" ;;
  esac
}

add_to_path() {
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) return ;;
  esac

  profile="$(pick_profile)"
  path_profile="$profile"
  path_line="export PATH=\"$INSTALL_DIR:\$PATH\""

  if [ -f "$profile" ] && grep -F "$path_line" "$profile" >/dev/null 2>&1; then
    path_action="configured"
    return
  fi

  {
    printf '\n# >>> Pi Black installer >>>\n'
    printf '%s\n' "$path_line"
    printf '# <<< Pi Black installer <<<\n'
  } >> "$profile"
  path_action="added"
}

cleanup() {
  if [ -n "$staged_runtime" ] && [ -e "$staged_runtime" ]; then
    rm -rf "$staged_runtime"
  fi
  if [ -n "$staged_launcher" ] && [ -e "$staged_launcher" ]; then
    rm -f "$staged_launcher"
  fi
  if [ -n "$backup_runtime" ] && [ -e "$backup_runtime" ]; then
    if [ ! -e "$RUNTIME_PATH" ]; then
      mv "$backup_runtime" "$RUNTIME_PATH"
    else
      rm -rf "$backup_runtime"
    fi
  fi
  if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
  fi
}

parse_args "$@"

if [ "$RELEASE" != "latest" ] &&
  ! printf '%s\n' "$RELEASE" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$'; then
  echo "Invalid release tag: $RELEASE." >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *)
    echo "install.sh supports macOS and Linux." >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  arm64 | aarch64) arch="arm64" ;;
  x86_64 | amd64) arch="x64" ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

platform="$os-$arch"
case "$platform" in
  darwin-arm64) platform_label="macOS Apple Silicon" ;;
  darwin-x64) platform_label="macOS Intel" ;;
  linux-arm64) platform_label="Linux arm64" ;;
  linux-x64) platform_label="Linux x64" ;;
  *)
    echo "Unsupported platform: $platform" >&2
    exit 1
    ;;
esac

archive="pi-$platform.tar.gz"
manifest="SHA256SUMS"
launcher="launcher.sh"

if [ -n "${PI_BLACK_RELEASES_URL:-}" ]; then
  base_url="$PI_BLACK_RELEASES_URL"
  release_label="$RELEASE"
elif [ "$RELEASE" = "latest" ]; then
  base_url="https://github.com/${REPOSITORY}/releases/latest/download"
  release_label="latest"
else
  base_url="https://github.com/${REPOSITORY}/releases/download/${RELEASE}"
  release_label="$RELEASE"
fi

require_command mktemp
require_command tar
require_command install

tmp_dir="$(mktemp -d)"
trap cleanup EXIT HUP INT TERM
archive_path="$tmp_dir/$archive"
manifest_path="$tmp_dir/$manifest"
launcher_path="$tmp_dir/$launcher"

step "Installing Pi Black"
step "Detected platform: $platform_label"
step "Resolved release: $release_label"
step "Downloading $archive"
download_file "$base_url/$manifest" "$manifest_path"
download_file "$base_url/$archive" "$archive_path" progress
download_file "$base_url/$launcher" "$launcher_path"

expected_archive_digest="$(manifest_digest "$manifest_path" "$archive")"
actual_archive_digest="$(file_sha256 "$archive_path")"
if [ -z "$expected_archive_digest" ] || [ "$actual_archive_digest" != "$expected_archive_digest" ]; then
  echo "Downloaded Pi Black archive checksum did not match." >&2
  exit 1
fi

expected_launcher_digest="$(manifest_digest "$manifest_path" "$launcher")"
actual_launcher_digest="$(file_sha256 "$launcher_path")"
if [ -z "$expected_launcher_digest" ] || [ "$actual_launcher_digest" != "$expected_launcher_digest" ]; then
  echo "Downloaded Pi Black launcher checksum did not match." >&2
  exit 1
fi

if ! tar -tzf "$archive_path" | awk '
  BEGIN { valid = 1; found = 0 }
  {
    path = $0
    sub(/\/$/, "", path)
    if (path == "pi") {
      found = 1
      next
    }
    if (index(path, "pi/") != 1) valid = 0
    count = split(path, parts, "/")
    for (i = 1; i <= count; i++) {
      if (parts[i] == ".." || parts[i] == "") valid = 0
    }
    found = 1
  }
  END { exit !(valid && found) }
'; then
  echo "The Pi Black archive has an unexpected layout." >&2
  exit 1
fi

tar -xzf "$archive_path" -C "$tmp_dir"
if [ ! -x "$tmp_dir/pi/pi" ]; then
  echo "The Pi Black executable was not found in the archive." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
staged_runtime="$INSTALL_DIR/.pi-black-runtime.$$"
staged_launcher="$INSTALL_DIR/.pi-black-launcher.$$"
backup_runtime="$INSTALL_DIR/.pi-black-runtime-backup.$$"
if [ -e "$staged_runtime" ] || [ -e "$staged_launcher" ] || [ -e "$backup_runtime" ]; then
  echo "A stale Pi Black installation staging path exists in $INSTALL_DIR." >&2
  exit 1
fi

mv "$tmp_dir/pi" "$staged_runtime"
printf '%s  %s\n' "$actual_archive_digest" "$archive" > "$staged_runtime/.pi-black-archive.sha256"
install -m 755 "$launcher_path" "$staged_launcher"

if [ -e "$RUNTIME_PATH" ]; then
  mv "$RUNTIME_PATH" "$backup_runtime"
fi
mv "$staged_runtime" "$RUNTIME_PATH"
staged_runtime=""
mv -f "$staged_launcher" "$COMMAND_PATH"
staged_launcher=""
if [ -e "$backup_runtime" ]; then
  rm -rf "$backup_runtime"
fi
backup_runtime=""

add_to_path
case "$path_action" in
  added)
    step "Added $INSTALL_DIR to PATH in $path_profile"
    step "Open a new terminal, or run: export PATH=\"$INSTALL_DIR:\$PATH\""
    ;;
  configured)
    step "$INSTALL_DIR is already configured in $path_profile"
    ;;
  *)
    step "$INSTALL_DIR is already on PATH"
    ;;
esac

printf 'Pi Black installed successfully. Run: pi-black\n'
