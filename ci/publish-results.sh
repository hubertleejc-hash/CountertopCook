#!/usr/bin/env bash
# Pushes screenshots and test summaries to a results branch (default: ci-results) so they can
# be viewed without signing in (Actions artifacts and logs require a GitHub login).
# Needs GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA and GITHUB_RUN_ID from the workflow.
set -euo pipefail

BRANCH=${1:-ci-results}
SRC=$(cd "$(dirname "$0")/.." && pwd)/ci-output
DEST=$(mktemp -d)

cp -R "$SRC/screenshots" "$DEST/" 2>/dev/null || true
cp "$SRC"/*.txt "$DEST/" 2>/dev/null || true
for f in "$SRC"/test-*.log "$SRC"/build.log; do
  [ -f "$f" ] && tail -n 5000 "$f" > "$DEST/$(basename "$f")"
done
echo "${GITHUB_SHA} run ${GITHUB_RUN_ID}" > "$DEST/COMMIT.txt"

cd "$DEST"
git init -q -b "$BRANCH"
git config user.name "github-actions"
git config user.email "github-actions@users.noreply.github.com"
git add -A && git commit -q -m "CI results for ${GITHUB_SHA}"
git push -f "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$BRANCH"
