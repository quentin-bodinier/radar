#!/usr/bin/env bash
# Install the Radar slash commands and scheduled task into ~/.claude/.
# Idempotent: re-running after `git pull` is a no-op when symlinks are already in place.
# Refuses to overwrite an existing real file at any target path — only proceeds when
# the target is missing or already a symlink (back-up or remove manually first).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="${HOME}/.claude"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
SCHEDULED_DIR="${CLAUDE_DIR}/scheduled-tasks"

if [[ ! -d "${CLAUDE_DIR}" ]]; then
  echo "ERROR: ${CLAUDE_DIR} does not exist. Install Claude Code first." >&2
  exit 1
fi

mkdir -p "${COMMANDS_DIR}" "${SCHEDULED_DIR}"

link_file() {
  local src="$1"
  local dst="$2"
  if [[ -L "${dst}" ]]; then
    # Already a symlink — replace if it points elsewhere
    local current
    current="$(readlink "${dst}")"
    if [[ "${current}" == "${src}" ]]; then
      echo "  ok    ${dst} -> ${src}"
      return 0
    fi
    echo "  relink ${dst} (was -> ${current})"
    ln -sfn "${src}" "${dst}"
    return 0
  fi
  if [[ -e "${dst}" ]]; then
    echo "  SKIP  ${dst} is a real file, not a symlink. Back it up and remove it, then re-run." >&2
    return 1
  fi
  echo "  link  ${dst} -> ${src}"
  ln -s "${src}" "${dst}"
}

link_dir() {
  local src="$1"
  local dst="$2"
  if [[ -L "${dst}" ]]; then
    local current
    current="$(readlink "${dst}")"
    if [[ "${current}" == "${src}" ]]; then
      echo "  ok    ${dst} -> ${src}"
      return 0
    fi
    echo "  relink ${dst} (was -> ${current})"
    ln -sfn "${src}" "${dst}"
    return 0
  fi
  if [[ -e "${dst}" ]]; then
    echo "  SKIP  ${dst} is a real dir, not a symlink. Back it up and remove it, then re-run." >&2
    return 1
  fi
  echo "  link  ${dst} -> ${src}"
  ln -s "${src}" "${dst}"
}

failed=0

echo "Linking skills into ${COMMANDS_DIR}:"
for name in radar radar-focus radar-act radar-commit; do
  link_file "${REPO_ROOT}/skills/${name}.md" "${COMMANDS_DIR}/${name}.md" || failed=1
done

echo "Linking scheduled task into ${SCHEDULED_DIR}:"
link_dir "${REPO_ROOT}/scheduled-tasks/radar-daily-rebuild" "${SCHEDULED_DIR}/radar-daily-rebuild" || failed=1

echo
if [[ ! -f "${REPO_ROOT}/state/config.json" ]]; then
  echo "Next step: create your config."
  echo "  cp state/config.example.json state/config.json"
  echo "  \$EDITOR state/config.json"
fi

if [[ ! -f "${REPO_ROOT}/state/commitments.json" ]]; then
  echo "  cp state/commitments.example.json state/commitments.json"
fi

echo
if [[ "${failed}" -ne 0 ]]; then
  echo "Install completed with skipped items. Resolve the SKIPs above and re-run." >&2
  exit 1
fi

echo "Install OK. Run /radar in Claude Code to generate today.html."
