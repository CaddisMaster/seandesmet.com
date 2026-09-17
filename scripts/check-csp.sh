#!/usr/bin/env bash
# The page side of the server's Content-Security-Policy (#29). Run on every
# pull request (check.yml) and before every deploy (deploy.yml).
#
# nginx sends (SETUP.md §9):
#   default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:;
#   base-uri 'none'; form-action 'none'; frame-ancestors 'none'
#
# So the page may use inline <style> and style="" attributes, and fonts and
# images only as data: URIs. Anything else is BLOCKED in the visitor's browser
# — with no error anywhere a maintainer would look. A script, a web-font link or
# an external image would pass every other check and then silently not work.
# This makes that fail here instead.
#
# ⚠️ If the page genuinely needs something new, the fix is to change the policy
# in SETUP.md §9 and on the box FIRST, then this list, then the page — not to
# weaken this script until it passes.
#
#   scripts/check-csp.sh              # reads index.html
#   scripts/check-csp.sh some.html    # reads another file
set -euo pipefail

page="${1:-index.html}"

# ⚠️ LOAD-BEARING. Every rule below is an absence check, and an absence check
# passes against the wrong file, an empty file, or a truncated one. Prove this
# is actually the page before trusting any "nothing found".
if ! grep -q '<style>' "$page" || ! grep -q '</html>' "$page"; then
  echo "::error::$page does not look like the page (no <style> or no </html>)," \
       "so an empty result below would prove nothing."
  exit 1
fi

# data: URIs are allowed, and the favicon's SVG inside one contains
# 'http://www.w3.org/2000/svg' — blank their payloads first so they can never
# match a rule. A data: URI ends at a quote (attributes) or a ")" (CSS url()).
stripped=$(sed -E 's/data:[^")]*/data:/g' "$page")

fail=0
rule() {
  local why="$1" pattern="$2" hits
  hits=$(printf '%s\n' "$stripped" | grep -niP "$pattern" || true)
  if [ -n "$hits" ]; then
    echo "::error::$why"
    printf '%s\n' "$hits" | cut -c1-160 | sed 's/^/  line /'
    fail=1
  fi
}

rule "A <script> — the CSP allows no script at all (default-src 'none')." \
     '<script\b'
rule "An inline event handler — that is script, and the CSP blocks it." \
     '\son[a-z]+\s*=\s*["'"'"']'
rule "A javascript: URL — script, blocked." \
     'javascript:'
rule "A frame, object, embed or form — blocked (default-src / form-action 'none')." \
     '<(iframe|frame|object|embed|form)\b'
rule "A <base> — blocked (base-uri 'none')." \
     '<base\b'
rule "A <link> that loads something from outside the page — only data: is allowed." \
     '<link\b[^>]*\brel="(stylesheet|preload|prefetch|modulepreload|manifest|icon|apple-touch-icon)"[^>]*\bhref="(?!data:)'
rule "An src, srcset or poster that is not a data: URI — images, media and frames must be embedded." \
     '\s(src|srcset|poster)\s*=\s*"(?!data:)'
rule "A CSS url() that is not a data: URI — fonts and images must be embedded." \
     'url\(\s*["'"'"']?(?!data:)'
rule "An @import — an external stylesheet, blocked." \
     '@import\b'

if [ "$fail" -ne 0 ]; then
  echo "The page uses something the server's CSP blocks. See the note at the top of $0."
  exit 1
fi

echo "Nothing in $page falls outside the CSP."
