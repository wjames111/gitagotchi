# gitagotchi — lib/pixel.sh
# Half-block pixel renderer (ux-spec §9.2): each cell prints ▀ with
# fg = top pixel, bg = bottom pixel — 24×18 px = 24 cols × 9 rows, plain ANSI.
# Render ladder: truecolor → ANSI-256 nearest → Tier-A ASCII sprites (§6).
#
# Sprite source: sprites-pixel.txt palette-indexed grids
#   (### <id> · :palette K=..P=.. · :frame <name> · 18 grid rows of 24 chars).
# Body palette derives from the user's linguist color with the exact formula
# from gitagotchi-species-gallery.html; K (eyes) and P (accent) stay species-owned.
# Blink is derived, not stored: WKW→WDW, KW→DD, WK→DD, DKD→DDD (gallery JS).
#
# Animation frames beyond idle_1/idle_2 are optional; when the sprite file
# gains :frame eat_1 / sleep_1 / … they are picked up automatically. Until
# then states fall back to idle frames + stage overlays (placeholders).

PIX_MODE=""            # T = truecolor, 256 = ANSI-256, "" = unavailable
declare -a PIX_SPECIES=()
declare -A PIXF PIXPAL PIXREF PIXTRIM PIX_HASFRAME PIXNAME

pix_detect_mode() {
  if [[ ${OPT_ASCII:-0} == 1 ]]; then PIX_MODE=""; return; fi
  case "${COLORTERM:-}" in
    *truecolor*|*24bit*) PIX_MODE=T; return ;;
  esac
  # terminals that do truecolor but don't always export COLORTERM
  case "${TERM_PROGRAM:-}" in
    iTerm.app|WezTerm|ghostty|vscode|Hyper|Tabby|Warp*) PIX_MODE=T; return ;;
  esac
  case "${TERM:-}" in
    *-direct|*truecolor*|xterm-kitty|iterm2*|alacritty|wezterm|foot*|ghostty*) PIX_MODE=T; return ;;
  esac
  local n; n=$(tput colors 2>/dev/null || echo 8)
  if (( n >= 256 )); then PIX_MODE=256; else PIX_MODE=""; fi
}

# locate the grid file: project override → bundled copy
pix_file() {
  if [[ -n ${GITAGOTCHI_PIXFILE:-} && -r ${GITAGOTCHI_PIXFILE:-} ]]; then
    printf '%s' "$GITAGOTCHI_PIXFILE"
  elif [[ -r "$BASE_DIR/../sprites-pixel.txt" ]]; then
    printf '%s' "$BASE_DIR/../sprites-pixel.txt"
  elif [[ -r "$SPRITE_DIR/sprites-pixel.txt" ]]; then
    printf '%s' "$SPRITE_DIR/sprites-pixel.txt"
  fi
}

pix_db_load() {
  local f; f=$(pix_file)
  [[ -n $f ]] || return 1
  PIX_SPECIES=(); PIXF=(); PIXPAL=(); PIXTRIM=(); PIX_HASFRAME=()
  local line id="" frame="" buf=""
  _flush() {
    if [[ -n $id && -n $frame && -n $buf ]]; then
      PIXF["$id/$frame"]=${buf%$'\n'}
      PIX_HASFRAME["$id/$frame"]=1
    fi
    buf=""
  }
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      "### "*)
        _flush; frame=""
        id=${line#\#\#\# }; id=${id%% *}
        PIX_SPECIES+=("$id")
        # reference linguist hex from the header, e.g. "(Zeruko · linguist Rust #dea584)"
        if [[ $line =~ \#[0-9a-fA-F]{6} ]]; then PIXREF[$id]=${BASH_REMATCH[0]}; fi ;;
      ":palette "*)
        _flush; frame=""
        PIXPAL[$id]=${line#:palette } ;;
      ":frame "*)
        _flush
        frame=${line#:frame } ;;
      "#"*|"") [[ -n $frame && -n $buf ]] && _flush && frame="" ;;
      *)
        [[ -n $frame ]] && buf+="$line"$'\n' ;;
    esac
  done < "$f"
  _flush
  # palettes.txt: extracted from the species gallery (tools/extract-palettes.sh)
  # — those hexes are the rendered visual truth for each species.
  local palf="$SPRITE_DIR/palettes.txt"
  [[ -r "$(dirname "$f")/palettes.txt" ]] && palf="$(dirname "$f")/palettes.txt"
  if [[ -r $palf ]]; then
    local pid phex prest
    while read -r pid phex prest; do
      [[ -n $pid && -n $prest ]] || continue
      PIXPAL[$pid]=$prest
      PIXREF[$pid]=$phex
    done < "$palf"
  fi
  # invented species names from the gallery (tools/extract-palettes.sh)
  local namef="$SPRITE_DIR/species-names.txt"
  [[ -r "$(dirname "$f")/species-names.txt" ]] && namef="$(dirname "$f")/species-names.txt"
  if [[ -r $namef ]]; then
    local nid nname
    while read -r nid nname; do
      [[ -n $nid && -n $nname ]] && PIXNAME[$nid]=$nname
    done < "$namef"
  fi
  pix_egg_register
  (( ${#PIX_SPECIES[@]} > 0 ))
}


# ── the shared pixel egg (hatch theater, §5.9) ───────────────────────────────
# The egg belongs to no species, so it lives here rather than in the sprite
# file: one grid + two crack frames, tinted by the owner's linguist color
# through the same relative-HSL palette as every pet.
pix_egg_register() {
  PIXPAL[egg]="O=#ead9bd D=#93805e W=#fdf6e3 K=#3a3226 S=#d3c19e"
  PIXREF[egg]="#ead9bd"
  PIXF[egg/idle_1]='........................
..........DDDD..........
.........DOOOOD.........
........DOWOOOOD........
.......DOWWOOOOOD.......
.......DOWOOOOOOD.......
......DOWOOOOOOOOD......
......DOOOOOOOOOOD......
......DOOOOOOOOOOD......
......DOOOOOOOOOOD......
......DOOOOOOOOOOD......
......DSOOOOOOOOSD......
......DSOOOOOOOSSD......
.......DSOOOOOSSD.......
.......DSSOOOSSSD.......
........DSSSSSSD........
.........DDDDDD.........
........................'
  PIX_HASFRAME[egg/idle_1]=1
  PIXF[egg/crack_1]='........................
..........DDDD..........
.........DOKOOD.........
........DOWOKOOD........
.......DOWWKOOOOD.......
.......DOWOOKOOOD.......
......DOWOOKOOOOOD......
......DOOOOOOOOOOD......
......DOOOOOOOOOOD......
......DOOOOOOOOOOD......
......DOOOOOOOOOOD......
......DSOOOOOOOOSD......
......DSOOOOOOOSSD......
.......DSOOOOOSSD.......
.......DSSOOOSSSD.......
........DSSSSSSD........
.........DDDDDD.........
........................'
  PIX_HASFRAME[egg/crack_1]=1
  PIXF[egg/crack_2]='........................
..........DDDD..........
.........DOKKOD.........
........DOKWOKOD........
.......DOWW.KOOOD.......
.......DOWKWKOOOD.......
......DOWOOK.KOOOD......
......DOOOOOKOOOOD......
......DOOOOOOOOOOD......
......DOOOOOOOOOOD......
......DOOOOOOOOOOD......
......DSOOOOOOOOSD......
......DSOOOOOOOSSD......
.......DSOOOOOSSD.......
.......DSSOOOSSSD.......
........DSSSSSSD........
.........DDDDDD.........
........................'
  PIX_HASFRAME[egg/crack_2]=1
  pix_books_register
  pix_ball_register
}

# ── the fetch ball (PR-merged reward) ────────────────────────────────────────
# A classic red rubber ball, 6×4 px → 6 cols × 2 half-block rows. Registered
# with its own palette and ref hex equal to its body color, so pix_palette
# applies a zero hue-shift: the ball stays red whatever the pet's language.
pix_ball_register() {
  PIXPAL[ball]="O=#e0483b D=#8a2b22 W=#ffd9d4 K=#000000 S=#b03328"
  PIXREF[ball]="#e0483b"
  PIXF[ball/idle_1]='.DDDD.
DWWOOD
DOOOSD
.DDDD.'
  PIX_HASFRAME[ball/idle_1]=1
}

# ── the book pile (curiosity ≥ 75 vignette) ─────────────────────────────────
# A floor prop, not a species: five books in a ragged pile at the stage wall,
# every one a different color and size — narrow red on top, wide purple on
# the bottom, page edges in W. Each book is one half-block row: bright cover
# on the top pixel, its darker shade underneath, so the pile reads shaded.
# Fixed palette (ref == hex → pix_palette passes it through exactly). NOTE:
# the letter B is reserved — pix_palette overwrites PC[B] with the beard.
pix_books_register() {
  PIXPAL[books]="R=#c65b4e r=#8f4038 P=#d2a047 p=#96702e S=#4a76b8 s=#33517e G=#5ea15f g=#3f6f40 V=#9a6fc4 v=#6b4a8c W=#e8e0cd"
  PIXREF[books]="#c65b4e"
  PIXF[books/idle_1]='............
............
...RRRRRW...
...rrrrrr...
..PPPPPPPW..
..pppppppp..
....SSSSSW..
....ssssss..
..GGGGGGGGW.
..ggggggggg.
.VVVVVVVVVW.
.vvvvvvvvvv.'
  PIX_HASFRAME[books/idle_1]=1
  # the narrow pile (same five books, squeezed): stages under ~55 cells wide
  # can't fit the wide pile beside a wandering pet — the corner would hide
  # it more than show it (learned the hard way; see the ≤105-col note)
  PIXF[books/narrow]='........
........
..RRRW..
..rrrr..
.PPPPPW.
.pppppp.
...SSSW.
...ssss.
..GGGGW.
..ggggg.
VVVVVVVW
vvvvvvvv'
  PIX_HASFRAME[books/narrow]=1
}

# ── the review spear (outbound reviews ≥ 3 this week) ───────────────────────
# HELD, not ambient: pix_render blits this into the pet's own grid at the
# right paw, bottom-aligned to the feet, so the pet visibly grips it. Letters
# X/Y/Z are reserved in pix_palette (silver head / wooden shaft / gold
# tassel) — the spear keeps its own colors inside any pet's palette.
declare -a PIX_SPEAR=(
  ".X."
  "XXX"
  ".X."
  ".YZ"
  ".Y."
  ".Y."
  ".Y."
  ".Y."
  ".Y."
  ".Y."
  ".Y."
  ".Y."
  ".Y."
  ".Y."
  ".Y."
  ".Y."
)

pix_species_count() { printf '%s' "${#PIX_SPECIES[@]}"; }

# vertical trim: drop fully-transparent pixel-row PAIRS of THIS frame, so pets
# stand on the ground (per-frame: eat frames carry bowl pixels at the bottom,
# hibernate cocoons are short — bottom-aligning per frame keeps feet grounded).
pix_trim() { # id frame → "r0 r1" (inclusive, aligned to half-block pairs)
  local key="$1/$2"
  [[ -n ${PIXTRIM[$key]:-} ]] && { printf '%s' "${PIXTRIM[$key]}"; return; }
  local r lo=99 hi=0
  local -a g; local IFS=$'\n'; g=(${PIXF[$key]:-}); unset IFS
  for r in "${!g[@]}"; do
    [[ ${g[r]//./} != "" ]] || continue
    (( r < lo )) && lo=$r
    (( r > hi )) && hi=$r
  done
  (( lo == 99 )) && { lo=0; hi=17; }
  (( lo % 2 )) && lo=$((lo-1))
  (( hi % 2 == 0 )) && hi=$((hi+1))
  PIXTRIM[$key]="$lo $hi"
  printf '%s' "${PIXTRIM[$key]}"
}

# ── palette (gallery-exact) ─────────────────────────────────────────────────
# Each species ships a hand-tuned :palette drawn for its reference linguist
# color (hex in the ### header). To keep "color = your top language" (plan.md
# §2) AND match the gallery pixel-for-pixel, we recolor by the RELATIVE HSL
# shift between the user's linguist hex and the species' reference hex:
# user lang == reference lang → the exact gallery palette. K (eyes) and P
# (accent: gills/beak/crest) are species-owned and never shift.
declare -A PC          # letter → "r;g;b"
PC_KEY=""
PIX_NIGHT=0            # scene_calc flips this after dark: the whole stage
                       # palette cools and dims (part of the cache key)
pix_palette() { # species_id linguist_hex faint(0/1)
  local id=$1 hex=$2 faint=$3
  local key="$id|$hex|$faint|${PIX_BEARD_RGB:-}|${PIX_NIGHT:-0}"
  [[ $PC_KEY == "$key" ]] && return
  PC_KEY=$key; PC=()
  local pal=${PIXPAL[$id]:-"O=$hex D=$hex W=#ffffff K=#22272e P=#f778ba R=$hex S=$hex"}
  local ref=${PIXREF[$id]:-$hex}
  local out
  out=$(awk -v hex="$hex" -v ref="$ref" -v pal="$pal" -v faint="$faint" \
        -v night="${PIX_NIGHT:-0}" '
    function hx(s,   i,c,v) { s=tolower(s); v=0
      for(i=1;i<=length(s);i++){ c=index("0123456789abcdef",substr(s,i,1))-1; v=v*16+c }
      return v }
    function hue2rgb(p,q,t) { if(t<0)t+=1; if(t>1)t-=1;
      if(t<1/6) return p+(q-p)*6*t; if(t<1/2) return q;
      if(t<2/3) return p+(q-p)*(2/3-t)*6; return p }
    function hsl2rgb(h,s,l,   q,p,r,g,b) {
      h=h-360*int(h/360); if(h<0)h+=360
      h=h/360; s=s/100; l=l/100
      if(s>1)s=1; if(s<0)s=0
      if(l>0.96)l=0.96; if(l<0.04)l=0.04
      if(s==0){r=g=b=l} else {
        q = l<0.5 ? l*(1+s) : l+s-l*s; p=2*l-q
        r=hue2rgb(p,q,h+1/3); g=hue2rgb(p,q,h); b=hue2rgb(p,q,h-1/3) }
      return int(r*255+0.5) ";" int(g*255+0.5) ";" int(b*255+0.5) }
    function tohsl(hexs,   r,g,b,mx,mn,l,s,h,d) {
      r=hx(substr(hexs,2,2))/255; g=hx(substr(hexs,4,2))/255; b=hx(substr(hexs,6,2))/255
      mx=(r>g?r:g); mx=(mx>b?mx:b); mn=(r<g?r:g); mn=(mn<b?mn:b)
      l=(mx+mn)/2
      if(mx==mn){h=0;s=0} else { d=mx-mn
        s = l>0.5 ? d/(2-mx-mn) : d/(mx+mn)
        if(mx==r) h=(g-b)/d+(g<b?6:0); else if(mx==g) h=(b-r)/d+2; else h=(r-g)/d+4
        h=h/6 }
      HH=h*360; SS=s*100; LL=l*100
      return "" }
    function dimc(c,   n,a,r,g,b) { if(faint!=1 && night!=1) return c
      n=split(c,a,";"); r=a[1]; g=a[2]; b=a[3]
      if(night==1){ r*=0.70; g*=0.75; b*=0.92 }   # moonlight: cool + dim
      if(faint==1){ r*=0.45; g*=0.45; b*=0.45 }
      return int(r) ";" int(g) ";" int(b) }
    BEGIN {
      tohsl(hex); uh=HH; us=SS; ul=LL
      tohsl(ref); rh=HH; rs=SS; rl=LL
      dh = uh - rh
      ks = (rs > 1) ? us / rs : 1
      kl = (rl > 1) ? ul / rl : 1
      same = (tolower(hex) == tolower(ref))
      n = split(pal, parts, " ")
      for (i = 1; i <= n; i++) {
        split(parts[i], kv, "=")
        letter = kv[1]; lhex = kv[2]
        if (letter == "K" || letter == "P" || same) {
          r=hx(substr(lhex,2,2)); g=hx(substr(lhex,4,2)); b=hx(substr(lhex,6,2))
          print letter "=" dimc(r ";" g ";" b)
        } else {
          tohsl(lhex)
          s2 = HH; # placeholder to keep awk happy
          ns = SS * ks; if (ns > 100) ns = 100
          nl = LL * kl
          print letter "=" dimc(hsl2rgb(HH + dh, ns, nl))
        }
      }
    }')
  local l v
  while IFS='=' read -r l v; do [[ -n $l ]] && PC[$l]=$v; done <<<"$out"
  # the beard letter (wisdom, §6.7): its shade is an identity trait — derived
  # from the account's CREATED timestamp (beard_color_for), handed in via
  # PIX_BEARD_RGB by pet_compose. Never hue-shifted with the pelt; painted by
  # pix_apply_beard, absent from every authored grid, so it costs nothing.
  local brgb=${PIX_BEARD_RGB:-209;212;218}
  [[ ${PIX_NIGHT:-0} == 1 ]] && { moonlit "$brgb"; brgb=$MLIT; }
  if [[ $faint == 1 ]]; then
    local br bg bb; IFS=';' read -r br bg bb <<<"$brgb"
    PC[B]="$(( br * 45 / 100 ));$(( bg * 45 / 100 ));$(( bb * 45 / 100 ))"
  else PC[B]=$brgb; fi
  # reserved letters X/Y/Z: the review spear (silver head / wooden shaft /
  # gold tassel) — blitted into the grid by pix_render, absent from every
  # authored sprite, so the injection costs nothing
  if [[ $faint == 1 ]]; then
    PC[X]="90;92;95"; PC[Y]="62;40;22"; PC[Z]="94;68;15"
  else
    PC[X]="200;204;212"; PC[Y]="138;90;50"; PC[Z]="210;153;34"
  fi
  if [[ ${PIX_NIGHT:-0} == 1 ]]; then
    local xl
    for xl in X Y Z; do moonlit "${PC[$xl]}"; PC[$xl]=$MLIT; done
  fi
}

# 256-color cache per palette entry (mode 256)
declare -A PC256
pc_256() { # "r;g;b" → 256 index (cached)
  local rgb=$1
  [[ -n ${PC256[$rgb]:-} ]] && { printf '%s' "${PC256[$rgb]}"; return; }
  local r=${rgb%%;*} rest=${rgb#*;} g b
  g=${rest%%;*}; b=${rest#*;}
  local hex; hex=$(printf '#%02x%02x%02x' "$r" "$g" "$b")
  PC256[$rgb]=$(hex_to_256 "$hex")
  printf '%s' "${PC256[$rgb]}"
}

pix_blink_row() { # gallery JS blink derivation, order matters
  local r=$1
  r=${r//WKW/WDW}; r=${r//KW/DD}; r=${r//WK/DD}; r=${r//DKD/DDD}
  printf '%s' "$r"
}

# locate the eye row and its two clusters (KW/WK runs) — shared by the
# spectacles and eye-bag overlays. Sets EYE_ROW, E1S/E1E, E2S/E2E.
pix_find_eyes() { # nameref grid → 0 if found
  local -n EG=$1
  EYE_ROW=-1 E1S=0 E1E=0 E2S=0 E2E=0
  local ri row i
  for ri in "${!EG[@]}"; do
    row=${EG[ri]}
    local -a cs=() ce=()
    i=0
    while (( i < ${#row} - 1 )); do
      if [[ ${row:i:2} == KW || ${row:i:2} == WK ]]; then
        local s=$i e=$((i + 1))
        while (( s > 0 )) && [[ ${row:s-1:1} == [KW] ]]; do s=$((s - 1)); done
        while (( e < ${#row} - 1 )) && [[ ${row:e+1:1} == [KW] ]]; do e=$((e + 1)); done
        cs+=("$s"); ce+=("$e"); i=$((e + 1))
      else i=$((i + 1)); fi
    done
    if (( ${#cs[@]} >= 2 )); then
      EYE_ROW=$ri
      E1S=${cs[0]} E1E=${ce[0]}
      E2S=${cs[${#cs[@]}-1]} E2E=${ce[${#ce[@]}-1]}
      return 0
    fi
  done
  return 1
}

# tired: bags under the eyes (energy < 25 — the pixel frazzle, §6.5).
# One row below each eye; below the bottom rim when glasses are on. Painted
# only over body pixels, so mouths, blush and rims are never clobbered.
pix_apply_bags() { # nameref grid, specs(0/1) — uses EYE_ROW/E1S…E2E from a
  local -n BG=$1   # pix_find_eyes call made on the PRISTINE grid (the specs
  local specs2=$2  # band fuses the eye row into one run, so find eyes first)
  (( ${EYE_ROW:--1} < 0 )) && return
  local br=$(( EYE_ROW + 1 + specs2 ))
  (( br >= ${#BG[@]} )) && return
  local row=${BG[br]} c
  for c in $(seq "$E1S" "$E1E") $(seq "$E2S" "$E2E"); do
    (( c < 0 || c >= ${#row} )) && continue
    case ${row:c:1} in O|S) row="${row:0:c}D${row:c+1}" ;; esac
  done
  BG[br]=$row
}

# wired: high energy (≥ 85) dilates the eyes — every pupil goes full black
# and the eye grows one pixel above and below, painted over body pixels only
# so outlines, blush and accents survive. All-K eyes no longer match the
# KW/WK blink patterns: a wired pet is too awake to blink, on purpose.
pix_apply_bigeyes() { # nameref grid — uses EYE_ROW/E1S…E2E from pix_find_eyes
  local -n BEG=$1
  (( ${EYE_ROW:--1} < 0 )) && return
  local r c row
  for r in $((EYE_ROW - 1)) "$EYE_ROW" $((EYE_ROW + 1)); do
    (( r < 0 || r >= ${#BEG[@]} )) && continue
    row=${BEG[r]}
    for c in $(seq "$E1S" "$E1E") $(seq "$E2S" "$E2E"); do
      (( c < 0 || c >= ${#row} )) && continue
      if (( r == EYE_ROW )); then
        [[ ${row:c:1} == W ]] && row="${row:0:c}K${row:c+1}"
      else
        case ${row:c:1} in O|S|W) row="${row:0:c}K${row:c+1}" ;; esac
      fi
    done
    BEG[r]=$row
  done
}

# curious: scrunched brows (curiosity ≥ 75) — a three-pixel bar over each
# eye, always with one clear pixel row between brow and eye so they never
# fuse, and shifted one pixel toward the nose for the knitted-inspector look.
# Painted over body pixels only, so heads whose foreheads are outline or
# transparent just skip it; when the wired dilation owns the rows around the
# eyes, the brows slide one row higher so both expressions survive.
pix_apply_brows() { # nameref grid, lift(0/1) — uses EYE_ROW/E1S…E2E
  local -n BRG=$1
  local lift=$2
  (( ${EYE_ROW:--1} < 0 )) && return
  local br=$(( EYE_ROW - 2 - lift ))   # EYE_ROW-1 stays clear, always
  (( br < 0 )) && return
  _brow() { # col
    local c=$1 line=${BRG[br]}
    (( c < 0 || c >= ${#line} )) && return
    case ${line:c:1} in O|S|W) BRG[br]="${line:0:c}K${line:c+1}" ;; esac
  }
  local c
  for c in $((E1E - 1)) "$E1E" $((E1E + 1)); do _brow "$c"; done   # left, nose-shifted →
  for c in $((E2S - 1)) "$E2S" $((E2S + 1)); do _brow "$c"; done   # right, nose-shifted ←
}

# elder spectacles: black circles around each eye with a bridge between —
# a K rim box around each eye cluster (one pixel above/below/beside) plus a
# thin bridge on the eye row. Applied to the grid before blink, so the eyes
# close behind the glasses.
pix_abs_hline() { # nameref grid, nameref rows, nameref spans — draw the
  # horizontal cut through the middle band row so the columns read as packs,
  # not slats; on a 2-row band the bottom row becomes the cut (half-block
  # rendering keeps the packs in the top half of the same terminal row)
  local -n gh=$1 hr=$2 hs=$3
  (( ${#hr[@]} < 2 )) && return
  local mi=$(( ${#hr[@]} / 2 ))
  local mrow=${hr[mi]} ha hL k line
  read -r ha hL <<<"${hs[mi]}"
  line=""
  for ((k = 0; k < hL; k++)); do line+=S; done
  local row=${gh[mrow]}
  gh[mrow]="${row:0:ha}$line${row:ha+hL}"
}

pix_apply_abs() { # nameref grid — fitness ≥ 80 chisels the belly (§6.5):
  # the W belly band splits into a six-pack; species without one (blobs,
  # bugs, shells) get definition lines carved into the lower body instead
  local -n ga=$1
  local r row applied=0
  local -a arows=() aspans=()
  for r in "${!ga[@]}"; do
    row=${ga[r]}
    [[ $row == *K* ]] && continue          # eye rows keep their whites
    [[ $row =~ WWWW ]] || continue
    local a=${row%%WWWW*} L=0
    a=${#a}
    while [[ ${row:a+L:1} == W ]]; do L=$((L + 1)); done
    (( L < 4 )) && continue
    local c1=$(( a + L / 3 )) c2=$(( a + (2 * L) / 3 ))
    row="${row:0:c1}S${row:c1+1}"
    row="${row:0:c2}S${row:c2+1}"
    ga[r]=$row
    applied=1
    arows+=("$r"); aspans+=("$a $L")
  done
  if (( applied )); then
    pix_abs_hline ga arows aspans        # the line through the middle
    return
  fi
  local n=${#ga[@]} carved=0
  for ((r = n / 2; r < n - 1 && carved < 3; r++)); do
    row=${ga[r]}
    [[ $row == *K* ]] && continue
    local i=0 cur=0 cs=0 best=0 bs=0
    while (( i <= ${#row} )); do
      if [[ ${row:i:1} == O ]]; then
        (( cur == 0 )) && cs=$i
        cur=$((cur + 1))
      else
        (( cur > best )) && { best=$cur; bs=$cs; }
        cur=0
      fi
      i=$((i + 1))
    done
    (( best < 4 )) && continue
    if (( best < 6 )); then                # narrow body: one center line
      local c1=$(( bs + best / 2 ))
      row="${row:0:c1}S${row:c1+1}"
    else
      local c1=$(( bs + best / 3 )) c2=$(( bs + (2 * best) / 3 ))
      row="${row:0:c1}S${row:c1+1}"
      row="${row:0:c2}S${row:c2+1}"
    fi
    ga[r]=$row
    carved=$((carved + 1))
    arows+=("$r"); aspans+=("$bs $best")
  done
  if (( carved )); then
    pix_abs_hline ga arows aspans
    return
  fi
  # nothing below the waist (jellyfish): carve the lowest body rows there are
  for ((r = n - 1; r >= 1 && carved < 2; r--)); do
    row=${ga[r]}
    [[ $row == *K* ]] && continue
    local i=0 cur=0 cs=0 best=0 bs=0
    while (( i <= ${#row} )); do
      if [[ ${row:i:1} == O ]]; then
        (( cur == 0 )) && cs=$i
        cur=$((cur + 1))
      else
        (( cur > best )) && { best=$cur; bs=$cs; }
        cur=0
      fi
      i=$((i + 1))
    done
    (( best < 4 )) && continue
    local c1=$(( bs + best / 3 )) c2=$(( bs + (2 * best) / 3 ))
    row="${row:0:c1}S${row:c1+1}"
    row="${row:0:c2}S${row:c2+1}"
    ga[r]=$row
    carved=$((carved + 1))
  done
}


pix_apply_mood() { # nameref grid, mood (1 smile · -1 frown; 0 keeps straight)
  # the mouth is the lone KK flanked by body pixels on a row without eye
  # clusters (KW/WK); a smile raises its corners, a frown drops them
  local -n gm=$1
  local mood=$2 r row m
  (( mood == 0 )) && return
  for r in "${!gm[@]}"; do
    row=${gm[r]}
    [[ $row == *KW* || $row == *WK* ]] && continue
    if [[ $row =~ [ORS]KK[ORS] ]]; then
      local pre=${row%%KK*}
      m=${#pre}
      local tr2=$(( mood > 0 ? r - 1 : r + 1 ))
      (( tr2 < 0 || tr2 >= ${#gm[@]} )) && return
      local trow=${gm[tr2]} c ch2
      for c in $((m - 1)) $((m + 2)); do
        ch2=${trow:c:1}
        case $ch2 in O|W|S|R) trow="${trow:0:c}K${trow:c+1}" ;; esac
      done
      gm[tr2]=$trow
      return
    fi
  done
}

pix_apply_beard() { # nameref grid, length 1..3 — wisdom's silver beard,
  local -n G=$1     # tapering from the chin: stubble → trimmed → full sage
  local blen=$2
  local er=$EYE_ROW s1=$E1S e2=$E2E
  local start=0
  if (( er >= 0 )); then
    start=$(( er + 3 ))
  else
    # profile sprites carry one eye, so pix_find_eyes came up empty — find
    # the lone KW/WK cluster and hang a small goatee off the chin instead
    local ri row i
    for ri in "${!G[@]}"; do
      row=${G[ri]}
      for ((i=0; i<${#row}-1; i++)); do
        if [[ ${row:i:2} == KW || ${row:i:2} == WK ]]; then
          er=$ri s1=$i e2=$((i + 1))
          while (( s1 > 0 )) && [[ ${row:s1-1:1} == [KW] ]]; do s1=$((s1-1)); done
          while (( e2 < ${#row}-1 )) && [[ ${row:e2+1:1} == [KW] ]]; do e2=$((e2+1)); done
          s1=$(( s1 - 2 )); e2=$(( e2 + 2 )); start=$(( er + 2 ))
          break 2
        fi
      done
    done
    (( er < 0 )) && return
  fi
  # never paint past the last body row: pix_trim was measured on the
  # authored grid, so anything hung below it gets sliced off at render
  local last=$(( ${#G[@]} - 1 ))
  while (( last > 0 )) && [[ ${G[last]} != *[!.]* ]]; do last=$((last-1)); done
  local br bi brow bs be x
  for ((br=0; br<blen; br++)); do
    bi=$(( start + br ))
    (( bi > last )) && break
    bs=$(( s1 + 1 + br )); be=$(( e2 - 1 - br ))
    (( bs < 0 )) && bs=0
    (( bs > be )) && break
    brow=${G[bi]}
    for ((x=bs; x<=be && x<${#brow}; x++)); do
      brow="${brow:0:x}B${brow:x+1}"
    done
    G[bi]=$brow
  done
}

pix_apply_specs() { # nameref to grid array
  local -n G=$1
  local ri row i
  local eyerow=-1 e1s=0 e1e=0 e2s=0 e2e=0
  for ri in "${!G[@]}"; do
    row=${G[ri]}
    local -a cs=() ce=()
    i=0
    while (( i < ${#row} - 1 )); do
      if [[ ${row:i:2} == KW || ${row:i:2} == WK ]]; then
        local s=$i e=$((i + 1))
        while (( s > 0 )) && [[ ${row:s-1:1} == [KW] ]]; do s=$((s - 1)); done
        while (( e < ${#row} - 1 )) && [[ ${row:e+1:1} == [KW] ]]; do e=$((e + 1)); done
        cs+=("$s"); ce+=("$e"); i=$((e + 1))
      else i=$((i + 1)); fi
    done
    if (( ${#cs[@]} >= 2 )); then
      eyerow=$ri
      e1s=${cs[0]} e1e=${ce[0]}
      e2s=${cs[${#cs[@]}-1]} e2e=${ce[${#ce[@]}-1]}
      break
    fi
  done
  (( eyerow < 0 )) && return

  _rim() { # row-string col → row-string with K at col (over body/space pixels)
    local rr=$1 c=$2
    (( c < 0 || c >= ${#rr} )) && { printf '%s' "$rr"; return; }
    case ${rr:c:1} in
      O|S|R|.|W) printf '%s' "${rr:0:c}K${rr:c+1}" ;;
      *) printf '%s' "$rr" ;;
    esac
  }
  # top and bottom rims over each eye's span
  local r c
  for r in $((eyerow - 1)) $((eyerow + 1)); do
    (( r < 0 || r >= ${#G[@]} )) && continue
    row=${G[r]}
    for ((c = e1s - 1; c <= e1e + 1; c++)); do row=$(_rim "$row" "$c"); done
    for ((c = e2s - 1; c <= e2e + 1; c++)); do row=$(_rim "$row" "$c"); done
    G[r]=$row
  done
  # side rims + a thin bridge between the inner rims (eye pixels untouched)
  row=${G[eyerow]}
  for c in $((e1s - 1)) $((e1e + 1)) $((e2s - 1)) $((e2e + 1)); do
    case ${row:c:1} in O|S|R|.) row="${row:0:c}K${row:c+1}" ;; esac
  done
  for ((c = e1e + 2; c <= e2s - 2; c++)); do
    case ${row:c:1} in O|S|R|.) row="${row:0:c}K${row:c+1}" ;; esac
  done
  G[eyerow]=$row
}

# hunger wears the silhouette: starving (< 20) shaves one pixel off each
# flank; stuffed (≥ 90) rounds the body out by one. The outline letter walks
# with the edge so the D rim survives, and run-length guards keep ears, legs,
# tails and whiskers out of it — eyes are interior and never touched.
pix_apply_body() { # nameref grid, mode (-1 skinny | 1 fat)
  local -n BG=$1
  local mode=$2 ri row n i
  for ri in "${!BG[@]}"; do
    row=${BG[ri]}; n=${#row}
    local out=$row
    i=0
    while (( i < n )); do
      if [[ ${row:i:1} == "." ]]; then i=$((i+1)); continue; fi
      local s=$i
      while (( i < n )) && [[ ${row:i:1} != "." ]]; do i=$((i+1)); done
      local e=$((i - 1)) len=$((i - s))
      if (( mode < 0 && len >= 8 )); then
        # the flank empties; the outline moves one column inward
        out="${out:0:s}.${out:s+1}"
        [[ ${row:s+1:1} == [OSRW] ]] && out="${out:0:s+1}${row:s:1}${out:s+2}"
        out="${out:0:e}.${out:e+1}"
        [[ ${row:e-1:1} == [OSRW] ]] && out="${out:0:e-1}${row:e:1}${out:e}"
      elif (( mode > 0 && len >= 6 )); then
        # the outline steps outward; body fill takes its old column
        if (( s > 0 )) && [[ ${row:s-1:1} == "." ]]; then
          out="${out:0:s-1}${row:s:1}${out:s}"
          [[ ${row:s+1:1} == [OSRW] ]] && out="${out:0:s}${row:s+1:1}${out:s+1}"
        fi
        if (( e < n - 1 )) && [[ ${row:e+1:1} == "." ]]; then
          out="${out:0:e+1}${row:e:1}${out:e+2}"
          [[ ${row:e-1:1} == [OSRW] ]] && out="${out:0:e}${row:e-1:1}${out:e+1}"
        fi
      fi
    done
    BG[ri]=$out
  done
}

# social: the tail wags (social ≥ 70) — appendages are the small pixel runs
# a gap away from the body in the lower half (tails, stubby arms; legs are
# equal-length pairs and stay planted). On the odd beat every appendage run
# swishes one pixel away from the body; rows where the tail is ATTACHED
# (no gap) don't move, so the base stays put and the tip wags — a bend, not
# a slide. Phase 0 is the canonical grid, so snapshots stay deterministic.
pix_apply_wag() { # nameref grid, phase(0/1)
  local -n WG=$1
  local phase=$2
  (( phase == 0 )) && return
  local ri row n
  for ((ri=9; ri<${#WG[@]}; ri++)); do
    row=${WG[ri]}; n=${#row}
    local -a rs=() re=()
    local i=0
    while (( i < n )); do
      if [[ ${row:i:1} == "." ]]; then i=$((i+1)); continue; fi
      local s=$i
      while (( i < n )) && [[ ${row:i:1} != "." ]]; do i=$((i+1)); done
      rs+=("$s"); re+=($((i - 1)))
    done
    (( ${#rs[@]} < 2 )) && continue
    local main=0 j
    for j in "${!rs[@]}"; do
      (( re[j] - rs[j] > re[main] - rs[main] )) && main=$j
    done
    local mlen=$(( re[main] - rs[main] + 1 ))
    for j in "${!rs[@]}"; do
      (( j == main )) && continue
      local len=$(( re[j] - rs[j] + 1 ))
      (( len >= mlen || len > 5 )) && continue   # legs (equal pairs) stay planted
      local seg=${row:rs[j]:len}
      if (( rs[j] > re[main] )); then            # right of the body → swish right
        (( re[j] + 1 < n )) && [[ ${row:re[j]+1:1} == "." ]] || continue
        row="${row:0:rs[j]}.${seg}${row:re[j]+2}"
      else                                       # left of the body → swish left
        (( rs[j] >= 1 )) && [[ ${row:rs[j]-1:1} == "." ]] || continue
        row="${row:0:rs[j]-1}${seg}.${row:re[j]+1}"
      fi
    done
    WG[ri]=$row
  done
}

# pix_render id frame blink → PIXOUT[] colored lines, PIXOUT_W cols, PIXOUT_H rows
# (uses current PC palette; cache key includes it)
declare -A PIXCACHE PIXCACHE_W PIXCACHE_H
declare -a PIXOUT
PIXOUT_W=0 PIXOUT_H=0
pix_blit() { # nameref dst, nameref src, top row, left col — '.' is transparent
  local -n bd=$1 bs=$2
  local top=$3 left=$4
  local i x ch srow drow dr dx w=${#bd[0]} h=${#bd[@]}
  for i in "${!bs[@]}"; do
    dr=$(( top + i ))
    (( dr < 0 || dr >= h )) && continue
    drow=${bd[dr]}
    srow=${bs[i]}
    for ((x=0; x<${#srow}; x++)); do
      ch=${srow:x:1}
      [[ $ch == "." ]] && continue
      dx=$(( left + x ))
      (( dx < 0 || dx >= w )) && continue
      drow="${drow:0:dx}${ch}${drow:dx+1}"
    done
    bd[dr]=$drow
  done
}

# critical health rolls in on the gurney: a white-sheet stretcher with carry
# poles, legs and chunky wheels, appended under the trimmed body (§6.5).
# Palette letters, so it recolors with the pet's linguist hue like the egg.
declare -a PIX_GURNEY=(
  "..DWWWWWWWWWWWWWWWWWWWWWWD.."
  "DDDDDDDDDDDDDDDDDDDDDDDDDDDD"
  ".......DD..........DD......."
  ".......DD..........DD......."
  "......KWWK........KWWK......"
  ".......KK..........KK......."
)

pix_render() {
  local id=$1 frame=$2 blink=$3 specs=${4:-0} tired=${5:-0} flip=${6:-0} body=${7:-0} mood=${8:-0} sixp=${9:-0} bigeye=${10:-0} brows=${11:-0} wag=${12:-0} beard=${13:-0} gurney=${14:-0} spear=${15:-0}
  # ASCII-era frame names → pixel two-frame names
  case $frame in
    sick) frame=sick_1 ;; celebrate) frame=celebrate_1 ;;
    belly|stretch|young) frame=idle_1 ;;
  esac
  [[ -n ${PIXF[$id/$frame]:-} ]] || frame=idle_1
  # the cocoon hides the body — hibernation shape stays canonical
  [[ $frame == hibernate_* ]] && body=0
  # sick, sleeping and cocooned faces carry their own expression — and none
  # of them stands guard: the spear waits by the door
  [[ $frame == sick_* || $frame == sleep_* || $frame == hibernate_* ]] && mood=0 bigeye=0 brows=0 wag=0 spear=0
  # the cocoon hides the chin too (the beard survives sleep — it's earned)
  [[ $frame == hibernate_* ]] && beard=0
  # dilation and brows are invisible behind elder spectacle rims
  [[ $specs == 1 ]] && bigeye=0 brows=0
  local ck="$id/$frame/$blink/$specs/$tired/$flip/$body/$mood/$sixp/$bigeye/$brows/$wag/$beard/$gurney/$spear/$PC_KEY/$PIX_MODE"
  if [[ -n ${PIXCACHE[$ck]:-} ]]; then
    local IFS=$'\n'; PIXOUT=(${PIXCACHE[$ck]}); unset IFS
    PIXOUT_W=${PIXCACHE_W[$ck]} PIXOUT_H=${PIXCACHE_H[$ck]}
    return
  fi
  local -a g; local IFS=$'\n'; g=(${PIXF[$id/$frame]}); unset IFS
  (( body != 0 )) && pix_apply_body g "$body"
  EYE_ROW=-1
  [[ $tired == 1 || $bigeye == 1 || $brows == 1 || $beard != 0 ]] && pix_find_eyes g
  (( bigeye )) && pix_apply_bigeyes g
  (( brows )) && pix_apply_brows g "$bigeye"
  [[ $specs == 1 ]] && pix_apply_specs g
  [[ $tired == 1 ]] && pix_apply_bags g "$specs"
  (( mood != 0 )) && pix_apply_mood g "$mood"
  (( sixp == 1 )) && pix_apply_abs g
  (( beard != 0 )) && pix_apply_beard g "$beard"
  (( wag == 1 )) && pix_apply_wag g 1
  if (( spear == 1 )); then
    # review duty: the pike blits into the pet's own grid at the right paw,
    # bottom-aligned to the trimmed feet so its butt rests on the ground.
    # The shaft lands just past the body's edge at shoulder height (rows
    # 4-12, measured AFTER the skinny/fat transform, ignoring tails), so
    # wide and narrow species alike grip it instead of wearing it. After
    # wag (a planted spear doesn't swish), before flip (a mirrored friend
    # grips it with the other paw).
    local strim sr1 srr srow2 rmax=15
    strim=$(pix_trim "$id" "$frame"); sr1=${strim##* }
    for ((srr=4; srr<=12; srr++)); do
      srow2=${g[srr]:-}
      while [[ $srow2 == *. ]]; do srow2=${srow2%.}; done
      (( ${#srow2} - 1 > rmax )) && rmax=$(( ${#srow2} - 1 ))
    done
    (( rmax > 21 )) && rmax=21
    pix_blit g PIX_SPEAR $(( sr1 - ${#PIX_SPEAR[@]} + 1 )) "$rmax"
  fi
  if (( flip )); then
    # mirror horizontally (compare view: the friend faces your pet) —
    # per-pixel letters, so reversing each row is the whole transform
    local fi frow rrow ci
    for fi in "${!g[@]}"; do
      frow=${g[fi]}; rrow=""
      for ((ci=${#frow}-1; ci>=0; ci--)); do rrow+=${frow:ci:1}; done
      g[fi]=$rrow
    done
  fi
  local trim r0 r1; trim=$(pix_trim "$id" "$frame"); r0=${trim%% *}; r1=${trim##* }
  if (( spear == 1 )); then
    # the pike can rise above a short pet's head — widen the render window
    # so the spearhead isn't trimmed away (r1 is odd, so this stays even)
    local sp0=$(( r1 - ${#PIX_SPEAR[@]} + 1 ))
    (( sp0 < 0 )) && sp0=0
    (( sp0 < r0 )) && r0=$sp0
  fi
  if [[ ${gurney:-0} != 0 ]]; then
    # rebuild as trimmed body + stretcher so no trimmed-away blank rows gap
    # the patient from the bed (6 rows keeps the half-block pairing even)
    # the bed is wider than the sprite grid so the carry poles stick out —
    # body rows pad to the stretcher width, pet centered on the sheet
    local gw=${#PIX_GURNEY[0]} bw=${#g[0]}
    local lp=$(( (gw - bw) / 2 )) rp pad=""
    rp=$(( gw - bw - lp ))
    local -a ng=(); local gy lpad rpad
    printf -v lpad '%*s' "$lp" ""; lpad=${lpad// /.}
    printf -v rpad '%*s' "$rp" ""; rpad=${rpad// /.}
    for ((gy=r0; gy<=r1; gy++)); do ng+=("${lpad}${g[gy]}${rpad}"); done
    if [[ $gurney == 1 ]]; then
      ng+=("${PIX_GURNEY[@]}")
      g=("${ng[@]}")
    else
      # entrance theater (§6.5): "s<K>" = the gurney rolls in from the right,
      # still K px out, pet standing by; "j<L>" = bed parked, pet mid-hop with
      # its feet L px off the ground. Canvas is 2 half-blocks taller than the
      # settled pose so the hop has headroom; each phase is its own cache key.
      local bh=${#ng[@]} H lift=0 sx=0 blank
      H=$(( bh + 8 ))
      printf -v blank '%*s' "$gw" ""; blank=${blank// /.}
      local -a cv=()
      for ((gy=0; gy<H; gy++)); do cv+=("$blank"); done
      case $gurney in s*) sx=${gurney#s} ;; j*) lift=${gurney#j} ;; esac
      if [[ $gurney == j* ]]; then
        pix_blit cv PIX_GURNEY $(( H - 6 )) 0          # parked bed behind
        pix_blit cv ng $(( H - lift - bh )) 0          # the leaping patient
      else
        pix_blit cv ng $(( H - bh )) 0                 # pet waiting on the ground
        pix_blit cv PIX_GURNEY $(( H - 6 )) "$sx"      # bed rolls past, in front
      fi
      g=("${cv[@]}")
    fi
    r0=0; r1=$(( ${#g[@]} - 1 ))
  fi
  # badge backend (lib/badge.sh): capture the fully composed letter grid —
  # every transform above included, blink applied — before it bakes into
  # ANSI half-blocks. Colors live in PC[letter] ("r;g;b"), set by pix_palette.
  if [[ ${PIX_CAPTURE:-0} == 1 ]]; then
    PIXGRID=()
    local cy crow
    for ((cy=r0; cy<=r1; cy++)); do
      crow=${g[cy]:-}
      [[ $blink == 1 ]] && crow=$(pix_blink_row "$crow")
      PIXGRID+=("$crow")
    done
  fi
  local w=${#g[0]} y x out line tc bc t b
  PIXOUT=()
  for ((y=r0; y<=r1; y+=2)); do
    local top=${g[y]:-} bot=${g[y+1]:-}
    if [[ $blink == 1 ]]; then top=$(pix_blink_row "$top"); bot=$(pix_blink_row "$bot"); fi
    line=""
    for ((x=0; x<w; x++)); do
      t=${top:x:1}; b=${bot:x:1}
      [[ -z $t ]] && t="."; [[ -z $b ]] && b="."
      tc=""; bc=""
      [[ $t != "." ]] && tc=${PC[$t]:-}
      [[ $b != "." ]] && bc=${PC[$b]:-}
      if [[ -z $tc && -z $bc ]]; then line+=" "
      elif [[ $PIX_MODE == T ]]; then
        if [[ -n $tc && -n $bc ]]; then line+=$'\e[38;2;'"$tc"$'m\e[48;2;'"$bc"$'m▀\e[0m'
        elif [[ -n $tc ]]; then line+=$'\e[38;2;'"$tc"$'m▀\e[0m'
        else line+=$'\e[38;2;'"$bc"$'m▄\e[0m'; fi
      else
        if [[ -n $tc && -n $bc ]]; then line+=$'\e[38;5;'"$(pc_256 "$tc")"$'m\e[48;5;'"$(pc_256 "$bc")"$'m▀\e[0m'
        elif [[ -n $tc ]]; then line+=$'\e[38;5;'"$(pc_256 "$tc")"$'m▀\e[0m'
        else line+=$'\e[38;5;'"$(pc_256 "$bc")"$'m▄\e[0m'; fi
      fi
    done
    PIXOUT+=("$line")
  done
  PIXOUT_W=$w PIXOUT_H=${#PIXOUT[@]}
  local joined; printf -v joined '%s\n' "${PIXOUT[@]}"
  PIXCACHE[$ck]=${joined%$'\n'}
  PIXCACHE_W[$ck]=$PIXOUT_W PIXCACHE_H[$ck]=$PIXOUT_H
}

# tiny sprite for the friends table (mockup: real pixel pets in the rows):
# the trimmed 24×18 grid resamples to 6×4 px → 6 cols × 2 half-block rows;
# each target pixel is the majority letter of its source block
declare -A PIXMINICACHE
declare -a PIXM
pix_render_mini() { # species_id linguist_hex → PIXM[0..1] (visible width 6)
  local id=$1 hex=$2
  local ck="$id|$hex|$PIX_MODE"
  if [[ -n ${PIXMINICACHE[$ck]:-} ]]; then
    local IFS=$'\n'; PIXM=(${PIXMINICACHE[$ck]}); unset IFS
    return 0
  fi
  PIXM=("      " "      ")
  [[ -n $PIX_MODE && -n ${PIXF[$id/idle_1]:-} ]] || return 1
  pix_palette "$id" "$hex" 0
  local -a g m=()
  local IFS=$'\n'; g=(${PIXF[$id/idle_1]}); unset IFS
  local trim r0 r1; trim=$(pix_trim "$id" idle_1); r0=${trim%% *}; r1=${trim##* }
  local h=$(( r1 - r0 + 1 )); (( h < 4 )) && { r0=0; r1=17; h=18; }
  local ty tx sy y0 y1 k ch row seg
  for ((ty=0; ty<4; ty++)); do
    local mrow=""
    y0=$(( r0 + ty * h / 4 )); y1=$(( r0 + (ty + 1) * h / 4 ))
    (( y1 <= y0 )) && y1=$(( y0 + 1 ))
    for ((tx=0; tx<6; tx++)); do
      local -A cnt=()
      for ((sy=y0; sy<y1; sy++)); do
        row=${g[sy]:-}
        seg=${row:tx*4:4}
        for ((k=0; k<${#seg}; k++)); do
          ch=${seg:k:1}
          [[ $ch != "." ]] && cnt[$ch]=$(( ${cnt[$ch]:-0} + 1 ))
        done
      done
      local best="." bestn=1
      for ch in "${!cnt[@]}"; do
        (( cnt[$ch] > bestn )) && { best=$ch; bestn=${cnt[$ch]}; }
      done
      mrow+=$best
    done
    m+=("$mrow")
  done
  PIXM=()
  local y x t b tc bc line
  for ((y=0; y<4; y+=2)); do
    line=""
    for ((x=0; x<6; x++)); do
      t=${m[y]:x:1}; b=${m[y+1]:x:1}
      tc=""; bc=""
      [[ $t != "." ]] && tc=${PC[$t]:-}
      [[ $b != "." ]] && bc=${PC[$b]:-}
      if [[ -z $tc && -z $bc ]]; then line+=" "
      elif [[ $PIX_MODE == T ]]; then
        if [[ -n $tc && -n $bc ]]; then line+=$'\e[38;2;'"$tc"$'m\e[48;2;'"$bc"$'m▀\e[0m'
        elif [[ -n $tc ]]; then line+=$'\e[38;2;'"$tc"$'m▀\e[0m'
        else line+=$'\e[38;2;'"$bc"$'m▄\e[0m'; fi
      else
        if [[ -n $tc && -n $bc ]]; then line+=$'\e[38;5;'"$(pc_256 "$tc")"$'m\e[48;5;'"$(pc_256 "$bc")"$'m▀\e[0m'
        elif [[ -n $tc ]]; then line+=$'\e[38;5;'"$(pc_256 "$tc")"$'m▀\e[0m'
        else line+=$'\e[38;5;'"$(pc_256 "$bc")"$'m▄\e[0m'; fi
      fi
    done
    PIXM+=("$line")
  done
  local joined; printf -v joined '%s\n' "${PIXM[@]}"
  PIXMINICACHE[$ck]=${joined%$'\n'}
  return 0
}

# half-scale sprite (12 px wide): real pets, shrunk — the social cameo
# renders the host and every visitor at this size so the party always fits.
# Majority downsample; eyes/accents win their block so the face survives.
declare -A PIXHALFCACHE PIXHALFCACHE_H
declare -a PIXH
pix_render_half() { # species_id linguist_hex [frame] → PIXH[] (visible width 12)
  local id=$1 hex=$2 frame=${3:-idle_1}
  case $frame in
    sick) frame=sick_1 ;; celebrate) frame=celebrate_1 ;;
    belly|stretch|young) frame=idle_1 ;;
  esac
  [[ -n ${PIXF[$id/$frame]:-} ]] || frame=idle_1
  local ck="$id|$hex|$frame|$PIX_MODE"
  if [[ -n ${PIXHALFCACHE[$ck]:-} ]]; then
    local IFS=$'\n'; PIXH=(${PIXHALFCACHE[$ck]}); unset IFS
    return 0
  fi
  PIXH=()
  [[ -n $PIX_MODE && -n ${PIXF[$id/idle_1]:-} ]] || return 1
  pix_palette "$id" "$hex" 0
  local -a g m=()
  local IFS=$'\n'; g=(${PIXF[$id/$frame]}); unset IFS
  local trim r0 r1; trim=$(pix_trim "$id" "$frame"); r0=${trim%% *}; r1=${trim##* }
  local h=$(( r1 - r0 + 1 )); (( h < 2 )) && { r0=0; r1=17; h=18; }
  local th=$(( (h + 1) / 2 )); (( th % 2 )) && th=$(( th + 1 ))
  local ty tx sy y0 y1 k ch row seg
  for ((ty=0; ty<th; ty++)); do
    local mrow=""
    y0=$(( r0 + ty * h / th )); y1=$(( r0 + (ty + 1) * h / th ))
    (( y1 <= y0 )) && y1=$(( y0 + 1 ))
    for ((tx=0; tx<12; tx++)); do
      local -A cnt=()
      for ((sy=y0; sy<y1; sy++)); do
        row=${g[sy]:-}
        seg=${row:tx*2:2}
        for ((k=0; k<${#seg}; k++)); do
          ch=${seg:k:1}
          [[ $ch != "." ]] && cnt[$ch]=$(( ${cnt[$ch]:-0} + 1 ))
        done
      done
      local best="."
      for ch in K P R; do
        [[ -n ${cnt[$ch]:-} ]] && { best=$ch; break; }
      done
      if [[ $best == "." ]]; then
        local bestn=1
        for ch in "${!cnt[@]}"; do
          (( cnt[$ch] > bestn )) && { best=$ch; bestn=${cnt[$ch]}; }
        done
      fi
      mrow+=$best
    done
    m+=("$mrow")
  done
  local y x t b tc bc line
  for ((y=0; y<th; y+=2)); do
    line=""
    for ((x=0; x<12; x++)); do
      t=${m[y]:x:1}; b=${m[y+1]:x:1}
      [[ -z $t ]] && t="."; [[ -z $b ]] && b="."
      tc=""; bc=""
      [[ $t != "." ]] && tc=${PC[$t]:-}
      [[ $b != "." ]] && bc=${PC[$b]:-}
      if [[ -z $tc && -z $bc ]]; then line+=" "
      elif [[ $PIX_MODE == T ]]; then
        if [[ -n $tc && -n $bc ]]; then line+=$'\e[38;2;'"$tc"$'m\e[48;2;'"$bc"$'m▀\e[0m'
        elif [[ -n $tc ]]; then line+=$'\e[38;2;'"$tc"$'m▀\e[0m'
        else line+=$'\e[38;2;'"$bc"$'m▄\e[0m'; fi
      else
        if [[ -n $tc && -n $bc ]]; then line+=$'\e[38;5;'"$(pc_256 "$tc")"$'m\e[48;5;'"$(pc_256 "$bc")"$'m▀\e[0m'
        elif [[ -n $tc ]]; then line+=$'\e[38;5;'"$(pc_256 "$tc")"$'m▀\e[0m'
        else line+=$'\e[38;5;'"$(pc_256 "$bc")"$'m▄\e[0m'; fi
      fi
    done
    PIXH+=("$line")
  done
  local joined; printf -v joined '%s\n' "${PIXH[@]}"
  PIXHALFCACHE[$ck]=${joined%$'\n'}
  return 0
}

# species id → mini glyph (friends list rows) — every one of the 50 pixel
# species gets its own face, worn in its owner's linguist color
declare -A PIX_MINI=(
  [axolotl]="≼o≽" [cat]="^ᴥ^" [fox]=">ᴥ<" [chick]="(o)>" [blob]="(oo)"
  [octopus]="o/|\\" [frog]="ôᴥô" [penguin]="(•>" [crab]="}o{"
  [dog]="∪ᴥ∪" [bunny]="(\/)" [bear]="ʕᴥʔ" [mouse]="<:3" [raccoon]="≫ᴥ≪"
  [panda]="●ᴥ●" [koala]="ʕΩʔ" [pig]="(ºº)" [hamster]="°ᴥ°" [deer]="\\ᴥ/"
  [goat]="~ᴥ~" [sheep]="@ᴥ@" [lion]="{ᴥ}" [unicorn]="∆ᴥ∆" [gecko]="e~e"
  [squirrel]="cᴥɔ" [hedgehog]="ΛᴥΛ" [monkey]="OᴥO" [tiger]="≡ᴥ≡" [wolf]="/ᴥ\\"
  [dragon]="<Δ>" [otter]="≈ᴥ≈" [sloth]="-ᴥ-" [owl]="{oo}" [duck]="<o)"
  [parrot]="(o)«" [bat]="^v^" [ghost]="~o~" [mushroom]="(∩)" [pufferfish]="{*}"
  [squid]="<o~" [jellyfish]="∩;;" [snail]="@__" [turtle]="(#)" [fish]="><>"
  [whale]="(O)~" [snake]="~:>" [caterpillar]="εεε" [spider]="}·{" [beetle]="(≡)"
  [ladybug]="(:)"
)
pix_mini() {
  local m=${PIX_MINI[$1]:-"(o)"}
  if [[ $TIER == A ]]; then
    case $1 in
      cat|fox|frog) m="^.^" ;; penguin) m="(v>" ;; axolotl) m="<o>" ;;
      *) [[ $m == *[![:ascii:]]* ]] && m="(o)" ;;   # pure-ASCII tier
    esac
  fi
  printf '%s' "$m"
}
pix_ascii_fallback() { # pixel species id → bundled .sprite species
  case $1 in
    axolotl|cat|chick|blob|octopus) printf '%s' "$1" ;;
    *) # deterministic cycle through the 5 drawn ASCII bodies
      local -a five=(axolotl blob cat chick octopus) i=0 s
      for s in "${PIX_SPECIES[@]}"; do
        [[ $s == "$1" ]] && break
        i=$((i+1))
      done
      printf '%s' "${five[i % 5]}" ;;
  esac
}
