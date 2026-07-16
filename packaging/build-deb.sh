#!/usr/bin/env bash
# Build a binary .deb for gitagotchi. The app is pure bash, so the package is
# Architecture: all — one artifact for every platform. Ships the runtime tree
# only (no tests/ or tools/): the executable resolves its lib/sprites/templates
# relative to its own real path, so /usr/bin/gh-pet is an absolute symlink into
# /usr/lib/gitagotchi and everything is found.
#
# usage: packaging/build-deb.sh <version> [outdir]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: build-deb.sh <version> [outdir]}
OUTDIR=${2:-dist}
PKG="gitagotchi_${VERSION}_all"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
root="$STAGE/$PKG"

install -d "$root/DEBIAN" "$root/usr/lib/gitagotchi" "$root/usr/bin"

# the runtime tree
cp gh-pet/gh-pet "$root/usr/lib/gitagotchi/"
cp -R gh-pet/lib gh-pet/sprites gh-pet/templates "$root/usr/lib/gitagotchi/"
cp gh-pet/README.md LICENSE "$root/usr/lib/gitagotchi/"
chmod +x "$root/usr/lib/gitagotchi/gh-pet"
# absolute target so the readlink resolver lands on the real dir (a relative
# target would be dirname'd against the caller's cwd)
ln -s /usr/lib/gitagotchi/gh-pet "$root/usr/bin/gh-pet"

cat > "$root/DEBIAN/control" <<EOF
Package: gitagotchi
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Depends: bash (>= 4.0), jq, curl
Maintainer: William James <wjames111@users.noreply.github.com>
Homepage: https://github.com/wjames111/gitagotchi
Description: Terminal Tamagotchi derived from your GitHub account
 gitagotchi is a terminal pet whose entire life is a pure function of your
 GitHub activity and the wall clock. Nothing is stored — delete the cache and
 the same pet hatches again, anywhere. Ships the gh-pet CLI (run as gh-pet).
EOF

mkdir -p "$OUTDIR"
dpkg-deb --build --root-owner-group "$root" "$OUTDIR/$PKG.deb"
echo "$OUTDIR/$PKG.deb"
