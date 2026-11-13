#!/usr/bin/env bash
# Print the installed Next.js version and the path of its bundled docs.
# Usage: find-next-docs.sh [project-dir]   (walks up from the dir, so it works in monorepo packages too)
set -euo pipefail

dir="$(cd "${1:-.}" && pwd)"
while [ "$dir" != "/" ]; do
  pkg="$dir/node_modules/next/package.json"
  if [ -f "$pkg" ]; then
    version="$(node -p "require('$pkg').version")"
    docs="$dir/node_modules/next/dist/docs"
    echo "next_version=$version"
    if [ -d "$docs" ]; then
      echo "docs=$docs"
      echo "app_router_docs=$docs/01-app"
    else
      echo "docs=MISSING (Next < 16.2 bundles no docs; suggest: npx @next/codemod@latest agents-md)"
    fi
    exit 0
  fi
  dir="$(dirname "$dir")"
done

echo "next is not installed under ${1:-.} or any parent" >&2
exit 1
