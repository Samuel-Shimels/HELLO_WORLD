#!/usr/bin/env bash
set -euo pipefail

# Cursor Linux updater (AppImage)
# - Detects architecture (x64/arm64)
# - Scrapes latest AppImage URL from https://cursor.com/download
# - Installs to ~/.local/bin and updates a stable symlink ~/.local/bin/cursor
# - Optionally creates a desktop entry ~/.local/share/applications/cursor.desktop

show_usage() {
  cat <<'EOF'
Usage: update-cursor.sh [options]

Options:
  --bin-dir DIR       Install directory for binaries (default: ~/.local/bin)
  --no-desktop        Skip creating/updating desktop entry
  --arch ARCH         Override architecture (x64 or arm64)
  -h, --help          Show this help

Notes:
- This script installs Cursor AppImage and maintains a stable symlink named 'cursor'.
- Ensure ~/.local/bin is on your PATH to launch 'cursor' from terminal.
EOF
}

BIN_DIR="${HOME}/.local/bin"
CREATE_DESKTOP=1
ARCH_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin-dir)
      [[ $# -ge 2 ]] || { echo "--bin-dir requires a value" >&2; exit 2; }
      BIN_DIR="$2"; shift 2;;
    --no-desktop)
      CREATE_DESKTOP=0; shift;;
    --arch)
      [[ $# -ge 2 ]] || { echo "--arch requires x64 or arm64" >&2; exit 2; }
      ARCH_OVERRIDE="$2"; shift 2;;
    -h|--help)
      show_usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2; show_usage; exit 2;;
  esac
done

mkdir -p "$BIN_DIR"

# Detect architecture
if [[ -n "$ARCH_OVERRIDE" ]]; then
  case "$ARCH_OVERRIDE" in
    x64|arm64) ARCH_PATH="$ARCH_OVERRIDE" ;;
    *) echo "Unsupported --arch: $ARCH_OVERRIDE (use x64 or arm64)" >&2; exit 2;;
  esac
else
  UNAME_M=$(uname -m || true)
  case "$UNAME_M" in
    x86_64) ARCH_PATH="x64" ;;
    aarch64|arm64) ARCH_PATH="arm64" ;;
    *) echo "Unsupported machine architecture: $UNAME_M" >&2; exit 2;;
  esac
fi

echo "Detected architecture: $ARCH_PATH"

# Fetch latest AppImage URL from the downloads page
DOWNLOAD_PAGE_URL="https://cursor.com/download"
HTML_CONTENT=$(curl -fsSL "$DOWNLOAD_PAGE_URL")

extract_url_with_python() {
  command -v python3 >/dev/null 2>&1 || return 1
  URL=$(python3 - "$ARCH_PATH" << 'PY' || true
import os, re, sys
arch = sys.argv[1]
html = sys.stdin.read()
pattern = rf"https://downloads\\.cursor\\.com/[^\"]*linux/{arch}/[^\"]*AppImage"
m = re.search(pattern, html)
if m:
    print(m.group(0))
PY
)
  if [[ -n "${URL:-}" ]]; then
    echo "$URL"
    return 0
  fi
  return 1
}

extract_url_with_awk() {
  # Use awk to avoid grep; match the first AppImage for the detected arch
  echo "$HTML_CONTENT" | awk -v arch="$ARCH_PATH" '
    match($0, "https://downloads.cursor.com/[^\"\047]*linux/" arch "/[^\"\047]*AppImage") {
      print substr($0, RSTART, RLENGTH)
      exit
    }
  '
}

LATEST_URL="$(extract_url_with_python || extract_url_with_awk || true)"

if [[ -z "$LATEST_URL" ]]; then
  echo "Failed to locate latest Cursor AppImage URL for arch=$ARCH_PATH from $DOWNLOAD_PAGE_URL" >&2
  exit 1
fi

echo "Latest Cursor AppImage: $LATEST_URL"

FILENAME=$(basename "$LATEST_URL")
TMP_DIR=$(mktemp -d)
TMP_FILE="$TMP_DIR/$FILENAME"

echo "Downloading to $TMP_FILE ..."
curl -fL "$LATEST_URL" -o "$TMP_FILE"

chmod +x "$TMP_FILE"
INSTALL_PATH="$BIN_DIR/$FILENAME"

# Move into place atomically
mv -f "$TMP_FILE" "$INSTALL_PATH"

# Update stable symlink
ln -sfn "$INSTALL_PATH" "$BIN_DIR/cursor"

echo "Installed: $INSTALL_PATH"
echo "Symlink:   $BIN_DIR/cursor"

# Create desktop entry if requested
if [[ "$CREATE_DESKTOP" -eq 1 ]]; then
  APPS_DIR="$HOME/.local/share/applications"
  mkdir -p "$APPS_DIR"
  DESKTOP_FILE="$APPS_DIR/cursor.desktop"
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Cursor
Comment=AI-first code editor
Exec=$BIN_DIR/cursor %U
Icon=cursor
Terminal=false
Categories=Development;IDE;Utility;
StartupWMClass=Cursor
EOF
  echo "Desktop entry updated: $DESKTOP_FILE"
fi

# Cleanup
rm -rf "$TMP_DIR"

echo
echo "Cursor updated successfully. If 'cursor' is not found, add $BIN_DIR to your PATH."
