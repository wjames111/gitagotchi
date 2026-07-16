#!/usr/bin/env bash
# Extract the per-species palettes from gitagotchi-species-gallery.html —
# the gallery's embedded `pal` objects are the rendered visual truth, so the
# terminal uses exactly those colors (recolored per user language at draw time).
# usage: tools/extract-palettes.sh <gallery.html> [out=sprites/palettes.txt]
set -euo pipefail
GALLERY=${1:?usage: extract-palettes.sh <gallery.html> [out]}
OUT=${2:-"$(dirname "$0")/../sprites/palettes.txt"}

# The extraction assumes `const SPECIES = [...];` on ONE physical line. If the
# gallery is ever reformatted (e.g. Prettier pretty-prints the array), sed
# matches nothing and jq on empty input exits 0 with no output — which would
# silently truncate palettes.txt/species-names.txt to empty. Extract once and
# assert non-empty at every stage so a format drift fails loudly instead.
species=$(sed -n 's/^const SPECIES = \(.*\);$/\1/p' "$GALLERY")
[[ -n $species ]] || { echo "error: no single-line 'const SPECIES = [...];' found in $GALLERY" >&2; exit 1; }

pal=$(jq -r '.[] | "\(.id) \(.hex) O=\(.pal.O) D=\(.pal.D) W=\(.pal.W) K=\(.pal.K) P=\(.pal.P) R=\(.pal.R) S=\(.pal.S)"' <<<"$species")
[[ -n $pal ]] || { echo "error: parsed 0 palettes from $GALLERY" >&2; exit 1; }
printf '%s\n' "$pal" > "$OUT"
echo "wrote $(wc -l < "$OUT" | tr -d ' ') palettes to $OUT"

# the gallery's invented species names are the displayed taxonomy
# (your pet is "a Randu", not "a raccoon" — the animal id stays internal)
NAMES="$(dirname "$OUT")/species-names.txt"
names=$(jq -r '.[] | "\(.id) \(.name)"' <<<"$species")
[[ -n $names ]] || { echo "error: parsed 0 species names from $GALLERY" >&2; exit 1; }
printf '%s\n' "$names" > "$NAMES"
echo "wrote $(wc -l < "$NAMES" | tr -d ' ') species names to $NAMES"
