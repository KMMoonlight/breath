#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
editor_root="$repository_root/Web/NotesEditor"

cd "$editor_root"
npm ci
npm run build
