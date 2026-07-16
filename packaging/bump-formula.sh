#!/usr/bin/env bash
# Point the Homebrew tap's formula at a new release: rewrite url + sha256 to
# the tagged source tarball and push. Needs GH_TOKEN with contents:write on
# the tap repo (a PAT stored as the TAP_TOKEN secret — the default workflow
# token can't push cross-repo). No-op-safe: run by hand or from release.yml.
#
# usage: GH_TOKEN=<pat> packaging/bump-formula.sh <version>
set -euo pipefail

VERSION=${1:?usage: bump-formula.sh <version>}
OWNER=wjames111
TAP=homebrew-gitagotchi
TARBALL="https://github.com/$OWNER/gitagotchi/archive/refs/tags/v${VERSION}.tar.gz"

echo "hashing $TARBALL"
SHA=$(curl -fsSL "$TARBALL" | sha256sum | cut -d' ' -f1)
[[ ${#SHA} == 64 ]] || { echo "bad sha: $SHA" >&2; exit 1; }

work=$(mktemp -d)
git clone --depth 1 "https://x-access-token:${GH_TOKEN}@github.com/$OWNER/$TAP.git" "$work"
formula="$work/Formula/gitagotchi.rb"

sed -i -E \
  -e "s|  url \".*\"|  url \"$TARBALL\"|" \
  -e "s|  sha256 \".*\"|  sha256 \"$SHA\"|" \
  "$formula"

cd "$work"
if git diff --quiet; then
  echo "formula already at $VERSION / $SHA — nothing to push"
  exit 0
fi
git config user.name "gitagotchi release"
git config user.email "wjames111@users.noreply.github.com"
git commit -am "gitagotchi $VERSION"
git push
echo "bumped $TAP to $VERSION"
