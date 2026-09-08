#!/usr/bin/env bash
#
# Rebase the `printalo` branch onto the upstream release we ship, build it,
# run the checks, and tag the result.
#
# Why this script exists
# ----------------------
# A fork that nobody rebases becomes a photograph. Three months later upstream
# has moved fifty files, a security fix lands there, and nobody can carry it
# over any more. The whole method of this fork depends on the patches staying
# few, small, and replayable — and on replaying them being one command.
#
# Why it anchors on the npm version and not on the newest tag
# -----------------------------------------------------------
# Upstream does not tag every release: at the time of writing the newest tag is
# v0.61.0 while npm serves 0.68.2 and `main` declares it in package.json.
# Anchoring on tags would freeze this fork three months behind the package we
# actually install on the server. So the anchor is the commit on upstream/main
# whose package.json declares the version published on npm — the same bits the
# server would get from `npm i -g pi-web-ui@<version>`.
#
#   ./scripts/sync-upstream.sh              sync to the current npm version
#   ./scripts/sync-upstream.sh 0.68.2       sync to a specific version
#   ./scripts/sync-upstream.sh --dry-run    say what it would do, touch nothing
#   ./scripts/sync-upstream.sh --no-build   rebase and tag, skip the checks
#
# --no-build exists for two moments: when you want to look at the rebase before
# spending ten minutes on a build, and for the test that exercises this script
# against a throwaway repository.
#
# On a rebase conflict it stops and says so. A conflict in a ten-line patch is
# five minutes of work, and it means upstream touched exactly the place we did
# — which is worth reading, not automating away.
set -euo pipefail

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
BRANCH="${BRANCH:-printalo}"
PKG="${PKG:-pi-web-ui}"
DRY=0
BUILD=1
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --no-build) BUILD=0 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) VERSION="$arg" ;;
  esac
done

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
stop() { printf '\033[1;31mKO \033[0m %s\n' "$*" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || stop "not a git repository"
[ -n "$(git status --porcelain)" ] && stop "working tree not clean — commit or stash first"

git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1 \
  || stop "no '$UPSTREAM_REMOTE' remote. git remote add $UPSTREAM_REMOTE https://github.com/xing-shuyin/pi-web-ui.git"

say "fetching $UPSTREAM_REMOTE"
git fetch --quiet --tags "$UPSTREAM_REMOTE"

if [ -z "$VERSION" ]; then
  VERSION="$(npm view "$PKG" version 2>/dev/null || true)"
  [ -n "$VERSION" ] || stop "cannot read the published version of $PKG from npm; pass one as an argument"
fi
say "target version: $VERSION"

# The newest commit on upstream/main that declares this version. Reading the
# first "version" field of package.json is enough: it is the package's own.
version_at() {
  git show "$1:package.json" 2>/dev/null \
    | sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

ANCHOR=""
for commit in $(git rev-list --max-count=400 "$UPSTREAM_REMOTE/main"); do
  if [ "$(version_at "$commit")" = "$VERSION" ]; then ANCHOR="$commit"; break; fi
done
[ -n "$ANCHOR" ] || stop "no commit in the last 400 of $UPSTREAM_REMOTE/main declares $VERSION"
say "anchor: $(git log -1 --format='%h %s' "$ANCHOR")"

BASE="$(git merge-base "$BRANCH" "$ANCHOR")"
if [ "$BASE" = "$ANCHOR" ] && git merge-base --is-ancestor "$ANCHOR" "$BRANCH"; then
  say "$BRANCH already sits on $VERSION — nothing to rebase"
else
  if [ "$DRY" = 1 ]; then
    say "would rebase $BRANCH onto $ANCHOR; patches that would replay:"
    git log --oneline "$BASE..$BRANCH" | sed 's/^/    /'
    exit 0
  fi
  say "rebasing $BRANCH onto $VERSION"
  git checkout --quiet "$BRANCH"
  git rebase "$ANCHOR" || stop "rebase stopped on a conflict. Fix it, 'git rebase --continue', then run this again."
fi

[ "$DRY" = 1 ] && { say "dry run: stopping before the build"; exit 0; }

if [ "$BUILD" = 1 ]; then
  say "npm ci"
  npm ci
  say "typecheck"; npm run typecheck
  say "test";      npm test
  say "build";     npm run build
else
  say "--no-build: skipping npm ci, typecheck, test and build"
fi

# Tag: v<upstream version>-printalo.<n>, n counting from 1 for this version.
n=1
while git rev-parse -q --verify "refs/tags/v${VERSION}-printalo.${n}" >/dev/null; do n=$((n+1)); done
TAG="v${VERSION}-printalo.${n}"
git tag -a "$TAG" -m "pi-web-ui $VERSION with the Printalo patches"
say "tagged $TAG"
echo
echo "  git push --force-with-lease origin $BRANCH && git push origin $TAG"
echo
echo "  The release workflow builds the tarball and attaches it to the GitHub"
echo "  Release for that tag. Then bump PI_WEB_UI_VERSIONE in ddra."
