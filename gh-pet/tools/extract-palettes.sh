#!/usr/bin/env bash
# Extract the per-species palettes from gitagotchi-species-gallery.html —
# the gallery's embedded `pal` objects are the rendered visual truth, so the
# terminal uses exactly those colors (recolored per user language at draw time).
# usage: tools/extract-palettes.sh <gallery.html> [out=sprites/palettes.txt]
set -euo pipefail
GALLERY=${1:?usage: extract-palettes.sh <gallery.html> [out]}
OUT=${2:-"$(dirname "$0")/../sprites/palettes.txt"}
sed -n 's/^const SPECIES = \(.*\);$/\1/p' "$GALLERY" \
  | jq -r '.[] | "\(.id) \(.hex) O=\(.pal.O) D=\(.pal.D) W=\(.pal.W) K=\(.pal.K) P=\(.pal.P) R=\(.pal.R) S=\(.pal.S)"' \
  > "$OUT"
echo "wrote $(wc -l < "$OUT" | tr -d ' ') palettes to $OUT"
# the gallery's invented species names are the displayed taxonomy
# (your pet is "a Randu", not "a raccoon" — the animal id stays internal)
NAMES="$(dirname "$OUT")/species-names.txt"
sed -n 's/^const SPECIES = \(.*\);$/\1/p' "$GALLERY" \
  | jq -r '.[] | "\(.id) \(.name)"' > "$NAMES"
echo "wrote $(wc -l < "$NAMES" | tr -d ' ') species names to $NAMES"
