#!/bin/sh

set -u

REPOSITORY="paoloanzn/pi-black"
RELEASES_BASE_URL="${PI_BLACK_RELEASES_URL:-https://github.com/${REPOSITORY}/releases/latest/download}"
case "$0" in
  */*) launcher_path="$0" ;;
  *) launcher_path="$(command -v "$0")" || exit 1 ;;
esac
script_dir="$(CDPATH= cd "$(dirname "$launcher_path")" && pwd)" || exit 1
RUNTIME_PATH="$script_dir/pi-black-runtime"
REAL_BINARY="$RUNTIME_PATH/pi"
INSTALLED_DIGEST_PATH="$RUNTIME_PATH/.pi-black-archive.sha256"
tmp_dir=""

cleanup() {
  if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
  fi
}

download_file() {
  url="$1"
  output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 2 --max-time 10 --retry 2 "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 10 -O "$output" "$url"
  else
    return 1
  fi
}

file_sha256() {
  path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" | sed 's/^.*= //'
  else
    return 1
  fi
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

installed_digest() {
  awk 'NR == 1 && length($1) == 64 && $1 !~ /[^0-9a-fA-F]/ { print tolower($1) }' "$INSTALLED_DIGEST_PATH"
}

updates_disabled() {
  case "${PI_BLACK_NO_UPDATE_CHECK:-}" in
    1 | [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss]) return 0 ;;
  esac
  case "${PI_OFFLINE:-}" in
    1 | [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss]) return 0 ;;
  esac
  return 1
}

select_archive() {
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64 | Darwin:aarch64) printf '%s\n' "pi-darwin-arm64.tar.gz" ;;
    Darwin:x86_64 | Darwin:amd64) printf '%s\n' "pi-darwin-x64.tar.gz" ;;
    Linux:arm64 | Linux:aarch64) printf '%s\n' "pi-linux-arm64.tar.gz" ;;
    Linux:x86_64 | Linux:amd64) printf '%s\n' "pi-linux-x64.tar.gz" ;;
    *) return 1 ;;
  esac
}

can_prompt() {
  if [ "${PI_BLACK_FORCE_UPDATE_CHECK:-}" = "1" ]; then
    return 0
  fi
  [ -t 0 ] && [ -t 2 ] && [ -r /dev/tty ] && [ -w /dev/tty ]
}

prompt_for_update() {
  if [ "${PI_BLACK_FORCE_UPDATE_CHECK:-}" = "1" ]; then
    {
      printf '\n✨ Update available for Pi Black.\n\n'
      printf '  1) Update now\n'
      printf '  2) Skip\n\n'
      printf 'Choice [1]:'
    } >&2
    if ! IFS= read -r answer; then
      answer=2
    fi
    printf '\n' >&2
  else
    {
      printf '\n✨ Update available for Pi Black.\n\n'
      printf '  1) Update now\n'
      printf '  2) Skip\n\n'
      printf 'Choice [1]:'
    } > /dev/tty
    if ! IFS= read -r answer < /dev/tty; then
      answer=2
    fi
    printf '\n' > /dev/tty
  fi

  case "$answer" in
    "" | 1 | y | Y | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

run_update_check() {
  updates_disabled && return
  can_prompt || return
  [ -x "$REAL_BINARY" ] || return
  [ -f "$INSTALLED_DIGEST_PATH" ] || return

  archive="$(select_archive)" || return
  manifest="SHA256SUMS"
  installer="install.sh"

  tmp_dir="$(mktemp -d 2>/dev/null)" || return
  trap cleanup EXIT HUP INT TERM
  manifest_path="$tmp_dir/$manifest"

  download_file "$RELEASES_BASE_URL/$manifest" "$manifest_path" >/dev/null 2>&1 || return
  latest_digest="$(manifest_digest "$manifest_path" "$archive")"
  current_digest="$(installed_digest)"
  [ -n "$latest_digest" ] || return
  [ -n "$current_digest" ] || return
  [ "$current_digest" = "$latest_digest" ] && return

  prompt_for_update || return

  installer_path="$tmp_dir/$installer"
  if ! download_file "$RELEASES_BASE_URL/$installer" "$installer_path" >/dev/null 2>&1; then
    printf 'WARNING: Could not download the Pi Black update; continuing with the installed version.\n' >&2
    return
  fi

  expected_installer_digest="$(manifest_digest "$manifest_path" "$installer")"
  actual_installer_digest="$(file_sha256 "$installer_path")"
  if [ -z "$expected_installer_digest" ] || [ "$actual_installer_digest" != "$expected_installer_digest" ]; then
    printf 'WARNING: The Pi Black installer checksum did not match; update cancelled.\n' >&2
    return
  fi

  if ! PI_BLACK_INSTALL_DIR="$script_dir" PI_BLACK_NO_UPDATE_CHECK=1 sh "$installer_path"; then
    printf 'WARNING: Pi Black could not be updated; continuing with the installed version.\n' >&2
  fi
}

if [ ! -x "$REAL_BINARY" ]; then
  printf 'Pi Black executable is missing or not executable: %s\n' "$REAL_BINARY" >&2
  exit 1
fi

run_update_check
cleanup
trap - EXIT HUP INT TERM
exec "$REAL_BINARY" "$@"
