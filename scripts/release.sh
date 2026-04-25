#!/usr/bin/env sh
# Gitbar release — bumps version, tags, publishes the GitHub release, and
# updates the Homebrew formula's sha256 to match the new tarball.
#
# Invoked via `flo release` (alias: `flo r`). See docs/RELEASING.md for the
# manual fallback if this script is unavailable.
set -eu

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$REPO_ROOT" ] || [ ! -f "$REPO_ROOT/Formula/gitbar.rb" ]; then
  echo "✗ Run this from the gitbar repo (Formula/gitbar.rb not found)." >&2
  exit 1
fi
cd "$REPO_ROOT"

SETTINGS="Sources/Gitbar/Views/SettingsView.swift"
INSTALL="install"
FORMULA="Formula/gitbar.rb"

for f in "$SETTINGS" "$INSTALL" "$FORMULA"; do
  if [ ! -f "$f" ]; then
    echo "✗ Missing $f — release layout has changed; update scripts/release.sh." >&2
    exit 1
  fi
done

for cmd in git gh curl shasum awk sed; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "✗ Required command not found: $cmd" >&2
    exit 1
  fi
done

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  printf "You're on '%s', not main. Continue anyway? [y/N] " "$BRANCH"
  read -r ans
  case "$ans" in
    y|Y|yes|Yes) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "✗ Working tree is dirty. Commit or stash first." >&2
  exit 1
fi

echo "→ Fetching tags…"
git fetch --tags --quiet

CURRENT=$(awk -F'"' '/^VERSION=/ {print $2; exit}' "$INSTALL")
if [ -z "$CURRENT" ]; then
  echo "✗ Could not parse VERSION from $INSTALL." >&2
  exit 1
fi
echo "Current version: $CURRENT"

LAST_TAG="v$CURRENT"
if git rev-parse "$LAST_TAG" >/dev/null 2>&1; then
  echo "Commits since $LAST_TAG:"
  git log --oneline "$LAST_TAG"..HEAD || true
else
  echo "(no tag $LAST_TAG yet)"
fi

printf "Bump type? [patch/minor/major] (default: patch): "
read -r BUMP
BUMP=${BUMP:-patch}

NEW=$(echo "$CURRENT" | awk -F. -v bump="$BUMP" '{
  if (NF != 3) { print "ERR_SHAPE"; exit }
  if (bump == "major")      print ($1+1)".0.0"
  else if (bump == "minor") print $1"."($2+1)".0"
  else if (bump == "patch") print $1"."$2"."($3+1)
  else                      print "ERR_BUMP"
}')

case "$NEW" in
  ERR_SHAPE) echo "✗ Unexpected version shape: $CURRENT" >&2; exit 1 ;;
  ERR_BUMP)  echo "✗ Unknown bump type: $BUMP" >&2; exit 1 ;;
esac

NEW_TAG="v$NEW"
if git rev-parse "$NEW_TAG" >/dev/null 2>&1; then
  echo "✗ Tag $NEW_TAG already exists." >&2
  exit 1
fi

echo
echo "Plan:"
echo "  $CURRENT → $NEW (tag $NEW_TAG)"
echo "  Edit:    $SETTINGS, $INSTALL"
echo "  Commit + push to origin/$BRANCH"
echo "  Tag $NEW_TAG and push tag"
echo "  Open \$EDITOR for release notes, then publish via gh"
echo "  Update $FORMULA sha256 from the new tarball, commit + push"
echo
printf "Proceed? [y/N] "
read -r ans
case "$ans" in
  y|Y|yes|Yes) ;;
  *) echo "Aborted — no changes made."; exit 1 ;;
esac

# --- Bump version in source files ---------------------------------------
# macOS sed needs `-i ''`; GNU sed needs `-i`. Pick portably.
sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

sed_inplace "s/Gitbar $CURRENT · Built for the menu bar/Gitbar $NEW · Built for the menu bar/" "$SETTINGS"
sed_inplace "s/^VERSION=\"$CURRENT\"/VERSION=\"$NEW\"/" "$INSTALL"

# Sanity-check the edits actually landed.
grep -q "Gitbar $NEW · Built for the menu bar" "$SETTINGS" \
  || { echo "✗ Failed to bump version in $SETTINGS." >&2; exit 1; }
grep -q "^VERSION=\"$NEW\"$" "$INSTALL" \
  || { echo "✗ Failed to bump version in $INSTALL." >&2; exit 1; }

git add "$SETTINGS" "$INSTALL"
git commit -m "bump to $NEW"
git push origin "$BRANCH"

# --- Tag and push -------------------------------------------------------
git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin "$NEW_TAG"

# --- Release notes ------------------------------------------------------
NOTES_FILE=$(mktemp -t "gitbar-$NEW_TAG-notes.XXXXXX")
{
  echo "<!-- Lines beginning with '#' followed by a space, and HTML comments,"
  echo "     are kept as-is. Save and quit to publish; leave the body empty"
  echo "     (excluding the commit list below) to abort. -->"
  echo
  echo "<one-sentence opener describing the shape of the release>"
  echo
  echo "### New"
  echo
  echo "- "
  echo
  echo "### Fixes"
  echo
  echo "- "
  echo
  echo "### Upgrade"
  echo
  echo "- Homebrew: \`brew upgrade gitbar\`"
  echo "- From source: \`./install\` rebuilds into \`~/Applications/Gitbar.app\`."
  echo
  echo "<!-- Commits in this release (for reference, strip before saving):"
  if git rev-parse "$LAST_TAG" >/dev/null 2>&1; then
    git log --oneline "$LAST_TAG".."$NEW_TAG"
  fi
  echo "-->"
} > "$NOTES_FILE"

EDITOR_CMD=${VISUAL:-${EDITOR:-vi}}
echo "→ Opening $EDITOR_CMD for release notes ($NOTES_FILE)…"
$EDITOR_CMD "$NOTES_FILE"

# Strip our HTML comment instructions/log block before publishing.
TMP_CLEAN=$(mktemp)
awk 'BEGIN{skip=0}
     /<!--/{skip=1}
     skip==0{print}
     /-->/{skip=0}' "$NOTES_FILE" > "$TMP_CLEAN"
mv "$TMP_CLEAN" "$NOTES_FILE"

if ! grep -q '[^[:space:]]' "$NOTES_FILE"; then
  echo "✗ Release notes are empty — aborting before gh release create." >&2
  echo "  Tag $NEW_TAG was pushed; rerun \`gh release create $NEW_TAG --notes-file …\` manually." >&2
  exit 1
fi

gh release create "$NEW_TAG" --title "$NEW_TAG" --notes-file "$NOTES_FILE"

# --- Homebrew formula ---------------------------------------------------
TARBALL_URL="https://github.com/brunokiafuka/gitbar/archive/refs/tags/$NEW_TAG.tar.gz"
echo "→ Computing sha256 of $TARBALL_URL…"
SHA=$(curl -sL --fail "$TARBALL_URL" | shasum -a 256 | awk '{print $1}')
if [ -z "$SHA" ] || [ ${#SHA} -ne 64 ]; then
  echo "✗ Failed to compute sha256 (got '$SHA')." >&2
  echo "  Tag and release exist; rerun the formula update manually." >&2
  exit 1
fi

sed_inplace "s|archive/refs/tags/v$CURRENT.tar.gz|archive/refs/tags/$NEW_TAG.tar.gz|" "$FORMULA"
# Replace the first sha256 line in the formula. There's only one at the top level.
sed_inplace "s|^  sha256 \"[0-9a-f]\{64\}\"|  sha256 \"$SHA\"|" "$FORMULA"

grep -q "$NEW_TAG.tar.gz" "$FORMULA" \
  || { echo "✗ Formula url did not update." >&2; exit 1; }
grep -q "$SHA" "$FORMULA" \
  || { echo "✗ Formula sha256 did not update." >&2; exit 1; }

git add "$FORMULA"
git commit -m "update Homebrew formula for $NEW_TAG"
git push origin "$BRANCH"

echo
echo "✓ Released Gitbar $NEW"
echo "  https://github.com/brunokiafuka/gitbar/releases/tag/$NEW_TAG"
