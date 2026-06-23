#!/usr/bin/env bash
#
# Solana Agent Ops Skill — installer
# Installs the agent-ops skill into your Claude Code skills directory.
# GreYat Labs
#
set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SKILL_REPO="https://github.com/solana-foundation/solana-dev-skill"

# Defaults
DEST_BASE="${HOME}/.claude"
ASSUME_YES=0
INSTALL_CORE=1

usage() {
  cat <<EOF
${BOLD}Solana Agent Ops Skill installer${RESET}

Usage: ./install.sh [options]

Options:
  -y, --yes          Non-interactive; accept all defaults
  -p, --project      Install into ./.claude (project-local) instead of ~/.claude
      --no-core      Skip installing the solana-dev-skill core dependency
  -h, --help         Show this help

Default install location: ${DEST_BASE}/skills/agent-ops
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1; shift ;;
    -p|--project) DEST_BASE="$(pwd)/.claude"; shift ;;
    --no-core) INSTALL_CORE=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${RESET}"; usage; exit 1 ;;
  esac
done

# ─── Banner ──────────────────────────────────────────────────────────────────
echo -e "${CYAN}${BOLD}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │        Solana Agent Ops Skill                │"
echo "  │  build agents that are safe to leave running │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${RESET}"
echo -e "  Install target: ${BOLD}${DEST_BASE}/skills/agent-ops${RESET}"
echo ""

if [[ "${ASSUME_YES}" -ne 1 ]]; then
  read -r -p "Proceed with installation? [Y/n] " reply
  case "${reply}" in [nN]*) echo "Aborted."; exit 0 ;; esac
fi

SKILLS_DIR="${DEST_BASE}/skills"
DEST="${SKILLS_DIR}/agent-ops"
mkdir -p "${SKILLS_DIR}"

# ─── 1. Core dependency: solana-dev-skill ────────────────────────────────────
if [[ "${INSTALL_CORE}" -eq 1 ]]; then
  if [[ -d "${SKILLS_DIR}/solana-dev" ]]; then
    echo -e "${GREEN}✓${RESET} core solana-dev skill already present — skipping"
  else
    echo -e "${CYAN}→${RESET} installing core dependency (solana-dev-skill)..."
    if git clone --depth 1 "${CORE_SKILL_REPO}" "${SKILLS_DIR}/solana-dev" 2>/dev/null; then
      echo -e "${GREEN}✓${RESET} core skill installed"
    else
      echo -e "${YELLOW}⚠${RESET}  could not clone core skill. agent-ops works standalone, but"
      echo -e "    cross-links to programs/security will be unresolved. Install it later:"
      echo -e "    ${BOLD}git clone ${CORE_SKILL_REPO} ${SKILLS_DIR}/solana-dev${RESET}"
    fi
  fi
else
  echo -e "${YELLOW}⚠${RESET}  --no-core set; skipping solana-dev-skill"
fi

# ─── 2. Install the agent-ops skill ──────────────────────────────────────────
echo -e "${CYAN}→${RESET} installing agent-ops skill..."
rm -rf "${DEST}"
mkdir -p "${DEST}"
cp -R "${SCRIPT_DIR}/skill/." "${DEST}/"
cp -R "${SCRIPT_DIR}/agents"   "${DEST}/agents"
cp -R "${SCRIPT_DIR}/commands" "${DEST}/commands"
cp -R "${SCRIPT_DIR}/rules"    "${DEST}/rules"
echo -e "${GREEN}✓${RESET} skill files copied to ${DEST}"

# ─── 3. CLAUDE.md ────────────────────────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/CLAUDE.md" ]]; then
  if [[ -f "${DEST_BASE}/CLAUDE.md" ]]; then
    cp "${DEST_BASE}/CLAUDE.md" "${DEST_BASE}/CLAUDE.md.bak"
    echo -e "${YELLOW}⚠${RESET}  backed up existing CLAUDE.md → CLAUDE.md.bak"
  fi
  cp "${SCRIPT_DIR}/CLAUDE.md" "${DEST}/CLAUDE.md"
  echo -e "${GREEN}✓${RESET} CLAUDE.md installed alongside the skill"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✓ Agent Ops skill installed.${RESET}"
echo ""
echo -e "  Try asking Claude Code:"
echo -e "    ${BOLD}\"design an autonomous Solana agent that claims rewards safely\"${RESET}"
echo -e "    ${BOLD}\"review my agent's send path for the cardinal retry rule\"${RESET}"
echo -e "    ${BOLD}\"/safety-review\"${RESET} before you go live"
echo ""
