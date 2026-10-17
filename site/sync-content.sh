#!/usr/bin/env bash
set -euo pipefail

# Aggregates co-located documentation into the Roq content/ directory.
#
# Sources -> destinations (markdown only):
#   docs/**/*.md                         -> content/docs/**
#   kubernetes/apps/<ns>/README.md       -> content/namespaces/<ns>/index.md
#   kubernetes/apps/<ns>/<app>/README.md -> content/apps/<ns>/<app>/index.md
#
# Each generated page gets deterministic frontmatter (title + link) injected,
# so Roq renders a stable URL regardless of the source file name.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="$ROOT_DIR/site"
CONTENT_DIR="$SITE_DIR/content"
MANIFEST="$SITE_DIR/.generated-manifest"

# --- helpers ---------------------------------------------------------------

# yaml_quote <text>  -> emits the text double-quoted and escaped for YAML.
yaml_quote() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

# generate_page <src> <dest> <default-title> <link>
# Copies src to dest with a generated frontmatter (title + link). Any existing
# frontmatter in src is stripped; the first markdown heading is used as the
# title when no better source is available.
generate_page() {
  local src="$1" dest="$2" default_title="$3" link="$4"
  mkdir -p "$(dirname "$dest")"

  local body
  body="$(mktemp)"

  # Strip a leading frontmatter block, if present.
  local in_fm=0
  while IFS= read -r line; do
    if [[ $in_fm -eq 0 && "$line" =~ ^---[[:space:]]*$ ]]; then
      in_fm=1
      continue
    fi
    if [[ $in_fm -eq 1 && "$line" =~ ^---[[:space:]]*$ ]]; then
      in_fm=0
      continue
    fi
    [[ $in_fm -eq 0 ]] && printf '%s\n' "$line" >> "$body"
  done < "$src"

  # Title: first markdown heading, else the provided default.
  local title
  title="$(grep -m1 -E '^#+[[:space:]]+' "$body" | sed -E 's/^#+[[:space:]]+//' || true)"
  title="${title:-$default_title}"

  {
    printf -- '---\n'
    printf 'title: %s\n' "$(yaml_quote "$title")"
    printf 'link: %s\n' "$(yaml_quote "$link")"
    printf -- '---\n\n'
    cat "$body"
  } > "$dest"

  rm -f "$body"
}

# --- clean previously generated content -------------------------------------

if [[ -f "$MANIFEST" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    rm -f "$CONTENT_DIR/$f"
  done < "$MANIFEST"
fi
find "$CONTENT_DIR" -type d -empty -delete 2>/dev/null || true
: > "$MANIFEST"

# --- global docs -------------------------------------------------------------

if [[ -d "$ROOT_DIR/docs" ]]; then
  while IFS= read -r -d '' f; do
    rel="${f#"$ROOT_DIR/docs"/}"
    slug="${rel%.*}" # strip extension
    generate_page "$f" "$CONTENT_DIR/docs/$rel" "$(basename "$slug")" "/docs/$slug/"
    printf 'docs/%s\n' "$rel" >> "$MANIFEST"
  done < <(find "$ROOT_DIR/docs" -type f \( -iname '*.md' -o -iname '*.adoc' \) -print0)
fi

# --- namespace-level docs -----------------------------------------------------

while IFS= read -r -d '' f; do
  ns="$(basename "$(dirname "$f")")"
  generate_page "$f" "$CONTENT_DIR/namespaces/$ns/index.md" "$ns" "/namespaces/$ns/"
  printf 'namespaces/%s/index.md\n' "$ns" >> "$MANIFEST"
done < <(find "$ROOT_DIR/kubernetes/apps" -mindepth 2 -maxdepth 2 -name 'README.md' -print0)

# --- app-level docs -----------------------------------------------------------

while IFS= read -r -d '' f; do
  app="$(basename "$(dirname "$f")")"
  ns="$(basename "$(dirname "$(dirname "$f")")")"
  generate_page "$f" "$CONTENT_DIR/apps/$ns/$app/index.md" "$app" "/apps/$ns/$app/"
  printf 'apps/%s/%s/index.md\n' "$ns" "$app" >> "$MANIFEST"
done < <(find "$ROOT_DIR/kubernetes/apps" -mindepth 3 -maxdepth 3 -name 'README.md' -print0)

echo "Synced documentation into $CONTENT_DIR"
