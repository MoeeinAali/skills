#!/usr/bin/env bash
# Run the project's quality gates in order; stop at the first failure.
# Usage: gates.sh [--quick|--full] [project-dir]
#   --quick  format, typecheck, lint, knip, unit tests (between edits)
#   default  + build
#   --full   + e2e
# Only package.json scripts that exist are run; missing ones are reported as skipped.
set -uo pipefail

mode="default"
case "${1:-}" in
  --quick|--full) mode="${1#--}"; shift ;;
esac
cd "${1:-.}"

if [ -f pnpm-lock.yaml ]; then pm="pnpm"
elif [ -f bun.lock ] || [ -f bun.lockb ]; then pm="bun"
elif [ -f yarn.lock ]; then pm="yarn"
else pm="npm"
fi

gates=(format:check typecheck lint knip test)
[ "$mode" != "quick" ] && gates+=(build)
[ "$mode" = "full" ] && gates+=(test:e2e)

has_script() { node -e "process.exit(require('./package.json').scripts?.['$1'] ? 0 : 1)"; }

for gate in "${gates[@]}"; do
  if ! has_script "$gate"; then
    echo "SKIP  $gate (no script)"
    continue
  fi
  echo "RUN   $gate"
  if ! "$pm" run -s "$gate"; then
    echo "FAIL  $gate"
    exit 1
  fi
  echo "PASS  $gate"
done
echo "ALL GATES PASSED ($mode)"
