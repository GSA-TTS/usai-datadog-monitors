#!/usr/bin/env bash
#
# assemble-changelog.sh — fold changelog.d/ fragment files into CHANGELOG.md.
#
# Each PR drops a fragment file `changelog.d/<id>-<slug>.<type>.md` instead of
# editing the shared `### Added` list head in CHANGELOG.md (GitHub #35 — the
# three-way-merge tax that hit #29/#30/#31/#32). At release we concatenate the
# fragments into the `## [Unreleased]` section, grouped by Keep a Changelog
# type, then delete them.
#
# Usage:
#   scripts/assemble-changelog.sh          assemble + delete fragments
#   scripts/assemble-changelog.sh --check  list pending fragments, change nothing (CI/dry-run)
#
# Toolchain-free by design: POSIX sh + awk, no Python. Run from anywhere; paths
# resolve relative to the repo root.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
FRAG_DIR="$REPO_ROOT/changelog.d"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

# Canonical Keep a Changelog section order.
TYPES="added changed deprecated removed fixed security"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

# Collect fragment files (exclude README.md). Nothing to do if none.
fragments=$(find "$FRAG_DIR" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' 2>/dev/null | sort || true)
if [ -z "$fragments" ]; then
  echo "No changelog fragments in changelog.d/ — nothing to assemble."
  exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "Pending changelog fragments:"
  echo "${fragments//$REPO_ROOT\//  }"
  exit 0
fi

# Title-case a type name for the "### Added" header.
title_case() {
  case "$1" in
    added)      echo "Added" ;;
    changed)    echo "Changed" ;;
    deprecated) echo "Deprecated" ;;
    removed)    echo "Removed" ;;
    fixed)      echo "Fixed" ;;
    security)   echo "Security" ;;
    *)          echo "$1" ;;
  esac
}

# Build the new-bullets block per type into a temp file keyed by type.
NEW_BLOCK=$(mktemp)
trap 'rm -f "$NEW_BLOCK"' EXIT

used_fragments=""
for t in $TYPES; do
  block=""
  for f in $fragments; do
    # Match files ending in .<type>.md
    case "$f" in
      *.$t.md)
        # Emit each non-empty logical bullet: prefix a "- " to the first line,
        # continuation lines keep their indentation. Blank lines separate bullets.
        body=$(awk 'NF{print} !NF{print ""}' "$f")
        block="${block}- ${body}"$'\n'
        used_fragments="${used_fragments} $f"
        ;;
    esac
  done
  if [ -n "$block" ]; then
    printf '@@TYPE@@%s\n%s' "$t" "$block" >> "$NEW_BLOCK"
  fi
done

if [ ! -s "$NEW_BLOCK" ]; then
  echo "Fragments found but none matched a known type (.added/.changed/.deprecated/.removed/.fixed/.security). Nothing assembled."
  exit 1
fi

# Merge NEW_BLOCK into CHANGELOG.md's [Unreleased] section with awk:
#  - within [Unreleased], merge each type's bullets into an existing
#    "### <Type>" subsection (insert right after its header) or create the
#    subsection in canonical order before the next "## " version header.
NEW_CONTENT=$(mktemp)
trap 'rm -f "$NEW_BLOCK" "$NEW_CONTENT"' EXIT

awk -v types="$TYPES" '
  BEGIN {
    n = split(types, torder, " ")
    # Read the new-bullets file passed as the first FILENAME.
  }
  # First file: the NEW_BLOCK. Parse into new[type] = concatenated bullets.
  FNR == NR {
    if ($0 ~ /^@@TYPE@@/) { cur = substr($0, 9); new[cur] = ""; next }
    if (cur != "") new[cur] = new[cur] $0 "\n"
    next
  }
  # Second file: CHANGELOG.md.
  FNR == 1 { inUnrel = 0 }
  {
    if ($0 ~ /^## \[Unreleased\]/) {
      print
      inUnrel = 1
      delete emitted
      next
    }
    # Leaving [Unreleased] at the next version header: flush any not-yet-emitted
    # new sections (types with no existing subsection) in canonical order.
    if (inUnrel && $0 ~ /^## /) {
      flush()
      inUnrel = 0
      print
      next
    }
    if (inUnrel && $0 ~ /^### /) {
      hdr = tolower($0); sub(/^### +/, "", hdr)
      print
      if (hdr in new && !(hdr in emitted)) {
        printf "%s", new[hdr]
        emitted[hdr] = 1
      }
      next
    }
    print
  }
  END { if (inUnrel) flush() }
  function flush(   i, t) {
    for (i = 1; i <= n; i++) {
      t = torder[i]
      if ((t in new) && !(t in emitted)) {
        printf "### %s%s\n", toupper(substr(t,1,1)) substr(t,2), ""
        printf "%s\n", new[t]
        emitted[t] = 1
      }
    }
  }
' "$NEW_BLOCK" "$CHANGELOG" > "$NEW_CONTENT"

mv "$NEW_CONTENT" "$CHANGELOG"
trap 'rm -f "$NEW_BLOCK"' EXIT

# Delete the consumed fragments (keep README.md).
for f in $used_fragments; do
  rm -f "$f"
done

echo "Assembled $(echo "$used_fragments" | wc -w | tr -d ' ') fragment(s) into CHANGELOG.md and removed them."
