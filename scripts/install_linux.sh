#!/usr/bin/env bash
set -euo pipefail
FROG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$FROG_ROOT/scripts/bootstrap.py" "$@"
