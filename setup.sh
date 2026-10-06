#!/bin/sh
# Installs upkg on the runner or inside a job container. POSIX sh: Alpine
# containers have no bash, and busybox wget instead of curl.
#
# Inputs (environment): INPUT_VERSION, INPUT_UPDATE, GITHUB_API_TOKEN, plus
# the runner's RUNNER_TEMP, GITHUB_PATH and GITHUB_OUTPUT.
set -eu

REPO="seuros/upkg"

main() {
  resolve_version
  echo "version=${VERSION}" >> "$GITHUB_OUTPUT"

  OS="$(uname -s)"
  ARCH="$(uname -m)"
  INSTALL_DIR="${RUNNER_TEMP}/upkg"
  BINARY="${INSTALL_DIR}/upkg"

  case "$OS" in
    Linux)
      case "$ARCH" in
        x86_64|amd64) cpu="x86_64" ;;
        aarch64|arm64) cpu="aarch64" ;;
        *) fail "Unsupported Linux architecture: ${ARCH}" ;;
      esac
      if is_musl; then
        install_target "${cpu}-unknown-linux-musl" tar.gz
      else
        install_target "${cpu}-unknown-linux-gnu" tar.gz
        # The gnu build needs the glibc of the runner image it was built on;
        # the static musl build runs on any Linux.
        if ! "$BINARY" --version >/dev/null 2>&1; then
          echo "::warning::upkg ${cpu}-unknown-linux-gnu does not run here (glibc too old?); using the static musl build."
          install_target "${cpu}-unknown-linux-musl" tar.gz
        fi
      fi
      ;;
    Darwin)
      case "$ARCH" in
        x86_64) install_target x86_64-apple-darwin tar.gz ;;
        arm64) install_target aarch64-apple-darwin tar.gz ;;
        *) fail "Unsupported macOS architecture: ${ARCH}" ;;
      esac
      ;;
    FreeBSD)
      case "$ARCH" in
        amd64|x86_64) install_target x86_64-unknown-freebsd tar.gz ;;
        *) fail "Unsupported FreeBSD architecture: ${ARCH}" ;;
      esac
      ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
      BINARY="${INSTALL_DIR}/upkg.exe"
      install_target x86_64-pc-windows-msvc zip
      ;;
    *) fail "Unsupported OS: ${OS}" ;;
  esac

  echo "$INSTALL_DIR" >> "$GITHUB_PATH"
  "$BINARY" --version

  if [ "${INPUT_UPDATE:-true}" = "true" ]; then
    refresh_metadata
  fi
}

resolve_version() {
  if [ "${INPUT_VERSION:-latest}" = "latest" ]; then
    fetch_api "${RUNNER_TEMP}/release.json" "https://api.github.com/repos/${REPO}/releases/latest"
    TAG="$(grep '"tag_name"' "${RUNNER_TEMP}/release.json" | head -n1 | cut -d'"' -f4)"
    [ -n "$TAG" ] || fail "Could not resolve the latest upkg release."
    VERSION="${TAG#upkg-v}"
  else
    VERSION="${INPUT_VERSION#v}"
    TAG="upkg-v${VERSION}"
  fi
}

# install_target TRIPLE EXT: download, verify against SHA256SUMS.txt, extract.
install_target() {
  archive="upkg-v${VERSION}-$1.$2"
  base="https://github.com/${REPO}/releases/download/${TAG}"

  echo "Downloading upkg ${VERSION} for $1..."
  download "${RUNNER_TEMP}/${archive}" "${base}/${archive}" || fail "Download failed: ${base}/${archive}"

  if download "${RUNNER_TEMP}/SHA256SUMS.txt" "${base}/SHA256SUMS.txt"; then
    expected="$(grep " ${archive}\$" "${RUNNER_TEMP}/SHA256SUMS.txt" | awk '{print $1}' | head -n1)"
    [ -n "$expected" ] || fail "No checksum for ${archive} in SHA256SUMS.txt"
    # Hash stdin: given a Windows path (D:\a\_temp), sha256sum escapes the
    # name and prefixes the hash with a backslash.
    if command -v sha256sum >/dev/null 2>&1; then
      actual="$(sha256sum < "${RUNNER_TEMP}/${archive}" | awk '{print $1}')"
    else
      actual="$(shasum -a 256 < "${RUNNER_TEMP}/${archive}" | awk '{print $1}')"
    fi
    [ "$expected" = "$actual" ] || fail "Checksum mismatch for ${archive} (expected ${expected}, got ${actual})"
    echo "Checksum verified: ${actual}"
  else
    echo "::warning::Could not download SHA256SUMS.txt for ${TAG}; skipping checksum verification."
  fi

  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  case "$2" in
    tar.gz) tar -xzf "${RUNNER_TEMP}/${archive}" -C "$INSTALL_DIR" ;;
    zip) unzip -q "${RUNNER_TEMP}/${archive}" -d "$INSTALL_DIR" ;;
  esac
}

is_musl() {
  [ -f /etc/alpine-release ] && return 0
  for loader in /lib/ld-musl-*; do
    [ -e "$loader" ] && return 0
  done
  return 1
}

# fetch_api OUT URL: authenticated first (dodges rate limits), then without
# a token; upkg is public, so a bad token must never break the install.
fetch_api() {
  if [ -n "${GITHUB_API_TOKEN:-}" ]; then
    download "$1" "$2" "Authorization: Bearer ${GITHUB_API_TOKEN}" && return 0
    echo "::warning::Authenticated request failed; retrying without token."
  fi
  download "$1" "$2" || fail "Request failed: $2"
}

# download OUT URL [HEADER]: curl, else wget (busybox on Alpine), 3 tries.
download() {
  tries=0
  until download_once "$@"; do
    tries=$((tries + 1))
    [ "$tries" -lt 3 ] || return 1
    sleep 2
  done
}

download_once() {
  if command -v curl >/dev/null 2>&1; then
    if [ -n "${3:-}" ]; then
      curl -fsSL -H "$3" -o "$1" "$2"
    else
      curl -fsSL -o "$1" "$2"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "${3:-}" ]; then
      wget -q --header="$3" -O "$1" "$2"
    else
      wget -q -O "$1" "$2"
    fi
  else
    fail "Installing upkg needs curl or wget."
  fi
}

refresh_metadata() {
  case "$OS" in
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        as_root apt-get update -y
      elif command -v apk >/dev/null 2>&1; then
        as_root apk update
      elif command -v dnf >/dev/null 2>&1; then
        as_root dnf makecache -y
      elif command -v yum >/dev/null 2>&1; then
        as_root yum makecache -y
      elif command -v pacman >/dev/null 2>&1; then
        as_root pacman -Sy --noconfirm
      elif command -v zypper >/dev/null 2>&1; then
        as_root zypper --non-interactive refresh
      fi
      ;;
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew update
      fi
      ;;
    FreeBSD)
      if command -v pkg >/dev/null 2>&1; then
        as_root pkg update -f
      fi
      ;;
  esac
}

# Job containers usually run as root without sudo; runners have sudo.
as_root() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v doas >/dev/null 2>&1; then
    doas "$@"
  else
    echo "::warning::Not root and neither sudo nor doas is available; skipped: $*"
  fi
}

fail() {
  echo "::error::$1"
  exit 1
}

main "$@"
