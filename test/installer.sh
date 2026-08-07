#!/bin/sh

set -eu

repo_root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
temporary_root="$(mktemp -d)"
cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

releases_dir="$temporary_root/releases"
staging_dir="$temporary_root/staging"
install_dir="$temporary_root/bin"
test_home="$temporary_root/home"
mkdir -p "$releases_dir" "$staging_dir" "$install_dir" "$test_home"

file_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  else
    shasum -a 256 "$1"
  fi
}

case "$(uname -s):$(uname -m)" in
  Darwin:arm64 | Darwin:aarch64)
    archive="pi-darwin-arm64.tar.gz"
    ;;
  Darwin:x86_64 | Darwin:amd64)
    archive="pi-darwin-x64.tar.gz"
    ;;
  Linux:arm64 | Linux:aarch64)
    archive="pi-linux-arm64.tar.gz"
    ;;
  Linux:x86_64 | Linux:amd64)
    archive="pi-linux-x64.tar.gz"
    ;;
  *)
    echo "Unsupported installer test platform." >&2
    exit 1
    ;;
esac

make_release() {
  version="$1"
  rm -rf "$staging_dir/pi"
  mkdir -p "$staging_dir/pi"
  cat > "$staging_dir/pi/pi" <<'EOF'
#!/bin/sh
script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
printf 'Pi Black %s: %s\n' "$(cat "$script_dir/VERSION")" "$*"
EOF
  chmod 755 "$staging_dir/pi/pi"
  printf '%s\n' "$version" > "$staging_dir/pi/VERSION"
  tar -C "$staging_dir" -czf "$releases_dir/$archive" pi
  cp "$repo_root/install.sh" "$releases_dir/install.sh"
  cp "$repo_root/launcher.sh" "$releases_dir/launcher.sh"
  (
    cd "$releases_dir"
    file_sha256 "$archive" > SHA256SUMS
    file_sha256 install.sh >> SHA256SUMS
    file_sha256 launcher.sh >> SHA256SUMS
  )
}

assert_equal() {
  expected="$1"
  actual="$2"
  label="$3"
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

make_release "1"
PATH="$install_dir:$PATH" \
HOME="$test_home" \
PI_BLACK_INSTALL_DIR="$install_dir" \
PI_BLACK_RELEASES_URL="file://$releases_dir" \
  sh "$repo_root/install.sh" > "$temporary_root/install.out"

test -x "$install_dir/pi-black"
test -x "$install_dir/pi-black-runtime/pi"
test -f "$install_dir/pi-black-runtime/.pi-black-archive.sha256"
assert_equal \
  "Pi Black 1: alpha" \
  "$(PI_BLACK_NO_UPDATE_CHECK=1 "$install_dir/pi-black" alpha)" \
  "installed launcher executes the standalone runtime"

assert_equal \
  "Pi Black 1: current" \
  "$(PI_BLACK_FORCE_UPDATE_CHECK=1 PI_BLACK_RELEASES_URL="file://$releases_dir" "$install_dir/pi-black" current 2> "$temporary_root/current.err")" \
  "current release does not prompt"
test ! -s "$temporary_root/current.err"

make_release "2"
printf '2\n' | PI_BLACK_FORCE_UPDATE_CHECK=1 PI_BLACK_RELEASES_URL="file://$releases_dir" \
  "$install_dir/pi-black" skipped > "$temporary_root/skip.out" 2> "$temporary_root/skip.err"
assert_equal "Pi Black 1: skipped" "$(cat "$temporary_root/skip.out")" "declined update keeps installed runtime"
grep -F "Update available for Pi Black" "$temporary_root/skip.err" >/dev/null

printf '\n' | PATH="$install_dir:$PATH" HOME="$test_home" \
  PI_BLACK_FORCE_UPDATE_CHECK=1 PI_BLACK_RELEASES_URL="file://$releases_dir" \
  "$install_dir/pi-black" updated > "$temporary_root/update.out" 2> "$temporary_root/update.err"
assert_equal "Pi Black 2: updated" "$(tail -n 1 "$temporary_root/update.out")" "accepted update runs new runtime"
grep -F "Update available for Pi Black" "$temporary_root/update.err" >/dev/null

make_release "3"
printf 'tampered\n' >> "$releases_dir/install.sh"
printf '\n' | PI_BLACK_FORCE_UPDATE_CHECK=1 PI_BLACK_RELEASES_URL="file://$releases_dir" \
  "$install_dir/pi-black" guarded > "$temporary_root/guarded.out" 2> "$temporary_root/guarded.err"
assert_equal "Pi Black 2: guarded" "$(cat "$temporary_root/guarded.out")" "tampered updater keeps installed runtime"
grep -F "installer checksum did not match" "$temporary_root/guarded.err" >/dev/null

assert_equal \
  "Pi Black 2: offline" \
  "$(PI_OFFLINE=1 PI_BLACK_FORCE_UPDATE_CHECK=1 PI_BLACK_RELEASES_URL="file://$releases_dir" "$install_dir/pi-black" offline 2> "$temporary_root/offline.err")" \
  "offline mode disables update detection"
test ! -s "$temporary_root/offline.err"

printf 'Installer and launcher tests passed\n'
