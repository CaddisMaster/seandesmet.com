#!/usr/bin/env bash
# The stack-tag gate. Run by BOTH the Deploy workflow (before anything is
# copied to the Droplet) and the Check workflow (on every pull request) —
# one file, so the gate a PR passes is the gate the deploy enforces (#23).
#
# Why it exists: a page naming a library the app no longer uses must never
# reach production. This came from budget-buddy#291, where the card advertised
# Chart.js for four releases after the app dropped it — nothing read this file,
# so nothing could catch it. The check lived in that repo's test suite until
# #299; it moved here with the page.
#
#   scripts/check-stack.sh              # reads index.html
#   scripts/check-stack.sh some.html    # reads another file
set -euo pipefail

# The file to read defaults to the page; a path argument lets the failure paths
# be exercised against a scratch copy without touching index.html.
page="${1:-index.html}"

# `|| true` on both: with `set -e` + `pipefail`, a selector that matches
# nothing would abort here — exiting 1 with NO explanation, right before
# the error message that says why. Fail loudly, not silently.
tags=$(grep -oE '<span class="stack-tag">[^<]*</span>' "$page" \
       | sed -E 's#.*>(.*)<.*#\1#' || true)
count=$(printf '%s\n' "$tags" | grep -c . || true)

# Quoted, so a two-word tag stays one line. Unquoted, `Let's Encrypt`
# prints as two entries and the listing contradicts the count.
echo "stack tags found ($count):"
printf '%s\n' "$tags" | sed 's/^/  /'

# ⚠️ THE LOAD-BEARING ASSERTION. Without it, a renamed class or a
# rewritten card makes the selector match nothing, `tags` is empty, the
# loop below runs zero times, and the check passes while asserting
# nothing at all. An absence test that cannot fail is worse than none.
if [ "$count" -lt 5 ]; then
  echo "::error::Only $count stack tags matched — the selector no longer" \
       "fits the markup, so this check is not actually reading the stack."
  exit 1
fi

# Front-end libraries the app has retired. Naming one here is a factual
# claim about what Budget Buddy uses, and it is wrong.
RETIRED='chart.js'

lower=$(printf '%s\n' "$tags" | tr '[:upper:]' '[:lower:]')
for r in $RETIRED; do
  # -x: whole-line match, so a tag merely containing the name is not a
  # false positive.
  if printf '%s\n' "$lower" | grep -qx "$r"; then
    echo "::error::The tech stack advertises retired '$r'. Budget Buddy" \
         "dropped it at 0.8.0 (budget-buddy#234) for ApexCharts."
    exit 1
  fi
done

echo "No retired library named."
