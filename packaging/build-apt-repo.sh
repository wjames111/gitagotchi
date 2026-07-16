#!/usr/bin/env bash
# Build a signed apt repository from one or more .deb files into a directory of
# static files, ready to publish as-is (e.g. GitHub Pages). After publishing at
# <URL>, users install by name with:
#
#   sudo install -d /etc/apt/keyrings
#   curl -fsSL <URL>/KEY.gpg | sudo tee /etc/apt/keyrings/gitagotchi.asc >/dev/null
#   echo "deb [signed-by=/etc/apt/keyrings/gitagotchi.asc] <URL> stable main" \
#     | sudo tee /etc/apt/sources.list.d/gitagotchi.list >/dev/null
#   sudo apt update && sudo apt install gitagotchi
#
# The package is Architecture: all (pure bash), but apt only looks in the
# binary-<native-arch> index, so the one Packages index is published under
# amd64, arm64, and all — any client finds it.
#
# Signing (required — apt rejects unsigned repos by default): provide the
# armored private signing key in APT_GPG_PRIVATE_KEY (and APT_GPG_PASSPHRASE if
# it has one). Generate a throwaway signing key once with:
#   gpg --batch --quick-gen-key 'gitagotchi apt <you@example.com>' default default never
#   gpg --armor --export-secret-keys <key-id>   # -> store as the APT_GPG_PRIVATE_KEY secret
#
# usage: packaging/build-apt-repo.sh <outdir> <deb>...
set -euo pipefail

OUT=${1:?usage: build-apt-repo.sh <outdir> <deb>...}
shift
[[ $# -gt 0 ]] || { echo "no .deb files given" >&2; exit 1; }

SUITE=stable
COMPONENT=main
ARCHES=(amd64 arm64 all)   # arch:all published under each so every client finds it
ORIGIN=gitagotchi
BASEURL=${APT_BASEURL:-https://wjames111.github.io/gitagotchi}

need() { command -v "$1" >/dev/null || { echo "missing required tool: $1" >&2; exit 1; }; }
need apt-ftparchive
need gpg
need gzip

# --- import the signing key ------------------------------------------------
[[ -n ${APT_GPG_PRIVATE_KEY:-} ]] || {
  echo "APT_GPG_PRIVATE_KEY is empty — cannot sign the repo" >&2
  exit 1
}
GNUPGHOME=$(mktemp -d); export GNUPGHOME
chmod 700 "$GNUPGHOME"
trap 'rm -rf "$GNUPGHOME"' EXIT
printf '%s\n' "$APT_GPG_PRIVATE_KEY" | gpg --batch --import
KEYID=$(gpg --list-secret-keys --with-colons | awk -F: '/^sec:/ {print $5; exit}')
[[ -n $KEYID ]] || { echo "no secret key found after import" >&2; exit 1; }

gpg_run() {   # clearsign/detach-sign helper, handles an optional passphrase
  if [[ -n ${APT_GPG_PASSPHRASE:-} ]]; then
    gpg --batch --yes --pinentry-mode loopback --passphrase "$APT_GPG_PASSPHRASE" \
        --local-user "$KEYID" "$@"
  else
    gpg --batch --yes --local-user "$KEYID" "$@"
  fi
}

# --- lay down the pool -----------------------------------------------------
rm -rf "$OUT"
mkdir -p "$OUT/pool/$COMPONENT"
for deb in "$@"; do
  [[ -f $deb ]] || { echo "not a file: $deb" >&2; exit 1; }
  cp "$deb" "$OUT/pool/$COMPONENT/"
done

cd "$OUT"

# --- indexes: one Packages, fanned out across the arches -------------------
pkgs=$(mktemp)
apt-ftparchive packages "pool/$COMPONENT" > "$pkgs"
[[ -s $pkgs ]] || { echo "apt-ftparchive produced an empty Packages index" >&2; exit 1; }
for arch in "${ARCHES[@]}"; do
  d="dists/$SUITE/$COMPONENT/binary-$arch"
  mkdir -p "$d"
  cp "$pkgs" "$d/Packages"
  gzip -kf "$d/Packages"
done
rm -f "$pkgs"

# --- Release, signed (InRelease inline + Release.gpg detached) -------------
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="$ORIGIN" \
  -o APT::FTPArchive::Release::Label="$ORIGIN" \
  -o APT::FTPArchive::Release::Suite="$SUITE" \
  -o APT::FTPArchive::Release::Codename="$SUITE" \
  -o APT::FTPArchive::Release::Components="$COMPONENT" \
  -o APT::FTPArchive::Release::Architectures="${ARCHES[*]}" \
  release "dists/$SUITE" > "dists/$SUITE/Release"

gpg_run --clearsign  -o "dists/$SUITE/InRelease"   "dists/$SUITE/Release"
gpg_run -abs         -o "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"

# --- public key + a human landing page -------------------------------------
gpg --armor --export "$KEYID" > KEY.gpg

cat > index.html <<HTML
<!doctype html><meta charset=utf-8><title>gitagotchi apt repo</title>
<style>body{font:16px/1.5 system-ui,sans-serif;max-width:44rem;margin:3rem auto;padding:0 1rem}
pre{background:#f4f4f4;padding:1rem;border-radius:8px;overflow:auto}code{font-family:ui-monospace,monospace}</style>
<h1>gitagotchi apt repository</h1>
<p>Install <code>gitagotchi</code> by name on Debian/Ubuntu:</p>
<pre>sudo install -d /etc/apt/keyrings
curl -fsSL $BASEURL/KEY.gpg | sudo tee /etc/apt/keyrings/gitagotchi.asc >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/gitagotchi.asc] $BASEURL stable main" \\
  | sudo tee /etc/apt/sources.list.d/gitagotchi.list >/dev/null
sudo apt update &amp;&amp; sudo apt install gitagotchi</pre>
<p>Then run <code>gh-pet</code>. Source: <a href="https://github.com/wjames111/gitagotchi">github.com/wjames111/gitagotchi</a>.</p>
HTML

echo "built signed apt repo in $OUT (key $KEYID)"
