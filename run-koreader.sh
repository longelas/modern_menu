#!/usr/bin/env bash
# Launch the extracted Linux AppImage with an Arch-safe device probe.
# Arch's /usr/bin/hwdetect (mkinitcpio) collides with KOReader's Kobo detection
# when running the stock AppImage directly.
#
# Also points ~/.config/koreader/plugins/modern_menu.koplugin at this repo's
# plugin so local edits are what KOReader loads.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTED="${ROOT}/squashfs-root"
APPRUN="${EXTRACTED}/AppRun"
PLUGIN_SRC="${ROOT}/modern_menu.koplugin"
PLUGIN_DST="${HOME}/.config/koreader/plugins/modern_menu.koplugin"

if [[ ! -x "${APPRUN}" ]]; then
  echo "Extracted AppImage not found. Run:"
  echo "  cd \"${ROOT}\" && ./koreader.AppImage --appimage-extract"
  exit 1
fi

if [[ ! -d "${PLUGIN_SRC}" ]]; then
  echo "Plugin folder missing: ${PLUGIN_SRC}"
  exit 1
fi

mkdir -p "$(dirname "${PLUGIN_DST}")"
# Replace a previous symlink/dir so we always load this checkout's plugin.
if [[ -e "${PLUGIN_DST}" || -L "${PLUGIN_DST}" ]]; then
  rm -rf "${PLUGIN_DST}"
fi
ln -s "${PLUGIN_SRC}" "${PLUGIN_DST}"
echo "Using plugin: ${PLUGIN_DST} -> ${PLUGIN_SRC}"

export KOREADER_FORCE_SDL=1
# Help SDL device identify as AppImage when running from extracted tree
export APPIMAGE="${ROOT}/koreader.AppImage"
export APPDIR="${EXTRACTED}"

exec "${APPRUN}" "$@"
