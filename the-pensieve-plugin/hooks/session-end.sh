#!/usr/bin/env bash
# session-end.sh — Pensieve SessionEnd hook (STUB, phase 2).
#
# Spec §8 describes an optional one-line daily log entry written to the vault
# at `daily/YYYY-MM-DD` summarizing what project was worked on. That write
# would go via Basic Memory's CLI (or a small helper that calls MCP), not by
# parsing markdown directly.
#
# Phase 1 ships this as a no-op so the hooks.json wiring can be flipped on
# later without restructuring. To activate, register this script under a
# SessionEnd entry in hooks.json and fill in the body below.

set -euo pipefail
exit 0
