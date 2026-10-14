#!/usr/bin/env bash
# Launch the extracted Linux AppImage with an Arch-safe device probe.
# Arch's /usr/bin/hwdetect (mkinitcpio) collides with KOReader's Kobo detection
# when running the stock AppImage directly.
#
# Points ~/.config/koreader/plugins/ at this repo's Modern Menu and at the
# local Quick Menu, Neo Quick Settings, and Simple UI checkouts so they can
# be tested together.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTED="${ROOT}/squashfs-root"
APPRUN="${EXTRACTED}/AppRun"
PLUGIN_DIR="${HOME}/.config/koreader/plugins"
# modern_menu is required. The others are optional local downloads.
PLUGINS=(
  modern_menu.koplugin
  quickmenu.koplugin
  neo_quicksetting.koplugin
  simpleui.koplugin
)

if [[ ! -x "${APPRUN}" ]]; then
  echo "Extracted AppImage not found. Run:"
  echo "  cd \"${ROOT}\" && ./koreader.AppImage --appimage-extract"
  exit 1
fi

mkdir -p "${PLUGIN_DIR}"
for name in "${PLUGINS[@]}"; do
  src="${ROOT}/${name}"
  # Neo Quick Settings is cloned as a repo whose plugin lives one level down.
  if [[ ! -f "${src}/_meta.lua" && -f "${src}/plugins/${name}/_meta.lua" ]]; then
    src="${src}/plugins/${name}"
  fi
  dst="${PLUGIN_DIR}/${name}"
  if [[ ! -d "${src}" ]]; then
    if [[ "${name}" == "modern_menu.koplugin" ]]; then
      echo "Plugin folder missing: ${src}"
      exit 1
    fi
    echo "Skipping ${name} (not present at ${src})"
    continue
  fi
  # Replace a previous symlink/dir so we always load this checkout's plugin.
  if [[ -e "${dst}" || -L "${dst}" ]]; then
    rm -rf "${dst}"
  fi
  ln -s "${src}" "${dst}"
  echo "Using plugin: ${dst} -> ${src}"
done

export KOREADER_FORCE_SDL=1
# Help SDL device identify as AppImage when running from extracted tree
export APPIMAGE="${ROOT}/koreader.AppImage"
export APPDIR="${EXTRACTED}"

exec "${APPRUN}" "$@"
