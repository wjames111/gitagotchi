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
  # ASCII sprites are the LAST resort, never a default: pixel art is what you
  # get unless you opt out with --ascii or the terminal genuinely can't show
  # color at all. A bare TERM=xterm reports only 8 colors via tput but renders
  # 256-color escapes fine, so "< 256 colors" must NOT mean "fall back to ASCII"
  # — that was demoting capable terminals. Prefer pixel whenever in doubt.
  if [[ ${OPT_ASCII:-0} == 1 ]]; then PIX_MODE=""; return; fi   # explicit opt-out
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
  # the ONLY automatic fall to ASCII: a terminal with no color at all
  # (TERM unset/dumb, or tput certain there are fewer than 8 colors).
  case "${TERM:-dumb}" in ""|dumb) PIX_MODE=""; return ;; esac
  local n; n=$(tput colors 2>/dev/null || echo 256)
  if (( n < 8 )); then PIX_MODE=""; else PIX_MODE=256; fi
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
  pix_ball_register
  pix_scene_register
}

# ── scene props (day/night + seasons, plan.md §11) ──────────────────────────
# A faithful 1:1 port of gitagotchi-seasons.html: the same chunky sky, weather
# and ground-dressing sprites the mockup draws, transcribed onto the half-block
# pixel grid. Three layers per mode — sky (sun + drifting clouds by day; a
# crescent moon + four-point stars by night), weather (petals · fireflies ·
# leaves · snow), and ground dressing (flowers · grass · leaf piles + pumpkin ·
# snow mounds + snowman). Fixed palettes with ref == their own hex, so
# pix_palette passes every color through exactly — like the books and the ball,
# never hue-shifted by the pet's language. Letters B/X/Y/Z stay off-limits
# (pix_palette overwrites them: beard + spear) — so the sun wears U, not the
# mockup's Y.
pix_scene_register() {
  # night sky — crescent moon + four-point stars, one cream-blue (HTML PAL.M)
  PIXPAL[moon]="M=#dce6f0"
  PIXREF[moon]="#dce6f0"
  PIXF[moon/idle_1]='..MMM.
MMMM..
MMM...
MMM...
MMMM..
..MMM.'
  PIX_HASFRAME[moon/idle_1]=1
  PIXPAL[star]="M=#dce6f0"
  PIXREF[star]="#dce6f0"
  PIXF[star/idle_1]='.M.
MMM
.M.
...'
  PIX_HASFRAME[star/idle_1]=1
  # day sky — the gold sun (HTML SUN2) + a slate drifting cloud (HTML CLOUD)
  PIXPAL[sun]="U=#ffd75f"
  PIXREF[sun]="#ffd75f"
  PIXF[sun/idle_1]='U...U...U
.UUUUUUU.
UUUUUUUUU
UUUUUUUUU
.UUUUUUU.
U...U...U'
  PIX_HASFRAME[sun/idle_1]=1
  PIXPAL[cloud]="C=#39424e"
  PIXREF[cloud]="#39424e"
  PIXF[cloud/idle_1]='..CCCC....
.CCCCCCCC.
CCCCCCCCCC
..........'
  PIX_HASFRAME[cloud/idle_1]=1
  # spring blossoms — the HTML FLOWER's two petal frames (pink · white), a
  # green stem beneath (letter P is white here: pix_palette honors K/P as their
  # own palette color, only B/X/Y/Z are stolen)
  PIXPAL[flower]="F=#f778ba P=#ffffff G=#2ea043"
  PIXREF[flower]="#f778ba"
  PIXF[flower/pink]='FF
FF
G.
..'
  PIX_HASFRAME[flower/pink]=1
  PIXF[flower/white]='PP
PP
.G
..'
  PIX_HASFRAME[flower/white]=1
  # summer grass tuft (HTML GRASS)
  PIXPAL[grass]="G=#2ea043"
  PIXREF[grass]="#2ea043"
  PIXF[grass/idle_1]='G.G
GGG'
  PIX_HASFRAME[grass/idle_1]=1
  # autumn — a leaf pile (HTML PILE) in each of the four LEAFC shades, and the
  # single falling leaf chunk (HTML weather 'leaf') in the same shades
  PIXPAL[pile]="L=#f0883e M=#db6d28 N=#c9510c Q=#d29922"
  PIXREF[pile]="#f0883e"
  PIXF[pile/a]='.LL.
LLLL'
  PIXF[pile/b]='.MM.
MMMM'
  PIXF[pile/c]='.NN.
NNNN'
  PIXF[pile/d]='.QQ.
QQQQ'
  PIX_HASFRAME[pile/a]=1; PIX_HASFRAME[pile/b]=1
  PIX_HASFRAME[pile/c]=1; PIX_HASFRAME[pile/d]=1
  PIXPAL[leaf]="A=#f0883e R=#db6d28 C=#c9510c D=#d29922"
  PIXREF[leaf]="#f0883e"
  PIXF[leaf/a]='AA
A.'
  PIXF[leaf/b]='RR
R.'
  PIXF[leaf/c]='CC
C.'
  PIXF[leaf/d]='DD
D.'
  PIX_HASFRAME[leaf/a]=1; PIX_HASFRAME[leaf/b]=1
  PIX_HASFRAME[leaf/c]=1; PIX_HASFRAME[leaf/d]=1
  # autumn pumpkin (HTML PUMPKIN) — orange body, green stub
  PIXPAL[pumpkin]="O=#e8762c g=#2ea043"
  PIXREF[pumpkin]="#e8762c"
  PIXF[pumpkin/idle_1]='.g.
OOO
OOO
...'
  PIX_HASFRAME[pumpkin/idle_1]=1
  # winter — snow mounds (HTML MOUND) and the snowman (HTML SNOWMAN, K eyes)
  PIXPAL[mound]="S=#e6edf3"
  PIXREF[mound]="#e6edf3"
  PIXF[mound/idle_1]='.SS.
SSSS'
  PIX_HASFRAME[mound/idle_1]=1
  PIXPAL[snowman]="S=#e6edf3 K=#22272e"
  PIXREF[snowman]="#e6edf3"
  PIXF[snowman/idle_1]='..SS..
.SKKS.
.SSSS.
SSSSSS'
  PIX_HASFRAME[snowman/idle_1]=1
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

# ── the reading pose (curiosity ≥ 75) ───────────────────────────────────────
# Was a floor prop (a five-book pile at the wall); now the pet HOLDS an open
# book and turns the pages (gitagotchi-reading.html). Like the spear it's a
# transform blitted into the pet's own grid — not a species, not a registered
# sprite. See pix_apply_reading below; the book's colors are reserved letters
# J/L/Q in pix_palette (cover / bright page / dim page), paws reuse K.

# ── the guardian spear (outbound reviews ≥ 3 this week) ─────────────────────
# The guardian pose (gitagotchi-spear.html): a full-height spear planted just
# outside the body, a leaf-blade head + red binding above, a gripping paw at
# mid-body, and a determined brow. Procedural from geometry (pix_apply_spear),
# not a fixed sprite. Reserved letters (pix_palette): X steel head · V steel
# shoulder · Y shaft light · Z shaft dark · T red binding · H tap dust; the
# knuckles/paw-outline/brow reuse K, the paw fill is the body's own O.

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
  # reserved letters X/V/Y/Z/T/H: the guardian spear — steel head / steel
  # shoulder / shaft light / shaft dark / red binding / tap dust. Blitted by
  # pix_apply_spear, absent from every authored sprite, so it costs nothing
  if [[ $faint == 1 ]]; then
    PC[X]="92;96;101"; PC[V]="62;66;72"; PC[Y]="62;40;19"; PC[Z]="42;27;12"; PC[T]="111;36;32"; PC[H]="26;28;32"
  else
    PC[X]="205;214;224"; PC[V]="138;147;160"; PC[Y]="138;90;43"; PC[Z]="95;61;28"; PC[T]="248;81;73"; PC[H]="58;64;72"
  fi
  # reserved letters J/L/Q: the reading book (blue cover / bright page / dim
  # page) — pix_apply_reading blits it into the grid; paws reuse K
  if [[ $faint == 1 ]]; then
    PC[J]="21;43;79"; PC[L]="110;108;102"; PC[Q]="90;88;78"
  else
    PC[J]="47;95;176"; PC[L]="244;240;226"; PC[Q]="201;195;173"
  fi
  if [[ ${PIX_NIGHT:-0} == 1 ]]; then
    local xl
    for xl in X V Y Z T H J L Q; do moonlit "${PC[$xl]}"; PC[$xl]=$MLIT; done
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

pix_apply_beard() { # nameref grid, length 1..3 — wisdom's beard, wrapped
  local -n G=$1     # AROUND the mouth (gitagotchi-elders_1.html): a mustache
  local blen=$2     # flanks the anchor, a tapered beard hangs below it
  # the anchor is the FACE, found like the mockup: the mouth (a KK run below
  # the eyes), else the beak (PP), else two rows under the eyes centered
  # between them. pix_find_eyes has already set EYE_ROW/E1S…E2E (two-eye
  # sprites); profile sprites (one eye) fall through to the lone-cluster scan.
  local er=$EYE_ROW s1=$E1S e2=$E2E
  local eyeC
  if (( er >= 0 )); then
    eyeC=$(( (s1 + e2) / 2 ))
  else
    # profile sprite (one eye) — find the lone KW/WK cluster
    local ri row i
    for ri in "${!G[@]}"; do
      row=${G[ri]}
      for ((i=0; i<${#row}-1; i++)); do
        if [[ ${row:i:2} == KW || ${row:i:2} == WK ]]; then
          er=$ri
          local ls=$i le=$((i + 1))
          while (( ls > 0 )) && [[ ${row:ls-1:1} == [KW] ]]; do ls=$((ls-1)); done
          while (( le < ${#row}-1 )) && [[ ${row:le+1:1} == [KW] ]]; do le=$((le+1)); done
          eyeC=$(( (ls + le) / 2 ))
          break 2
        fi
      done
    done
    # still nothing — the eyes are bare K's (e.g. the crab's stalks); the
    # mockup's last resort is the first row carrying any K, centered on them
    if (( er < 0 )); then
      local kc kn
      for ri in "${!G[@]}"; do
        row=${G[ri]} kc=0 kn=0
        for ((i=0; i<${#row}; i++)); do
          [[ ${row:i:1} == K ]] && { kc=$((kc + i)); kn=$((kn + 1)); }
        done
        (( kn > 0 )) && { er=$ri; eyeC=$(( kc / kn )); break; }
      done
    fi
    (( er < 0 )) && return
  fi

  # anchor row + center: mouth (KK+, anywhere below the eyes), then beak
  # (PP+, within three rows), then the chin fallback
  local arow=-1 ac=$eyeC r i row j e
  for ((r=er+1; r<${#G[@]}; r++)); do
    row=${G[r]}
    for ((i=0; i<${#row}-1; i++)); do
      if [[ ${row:i:2} == KK ]]; then
        e=$i
        while (( e < ${#row} )) && [[ ${row:e:1} == K ]]; do e=$((e+1)); done
        arow=$r; ac=$(( i + (e - i) / 2 )); break 2
      fi
    done
  done
  if (( arow < 0 )); then
    for ((r=er+1; r<er+4 && r<${#G[@]}; r++)); do
      row=${G[r]}
      for ((i=0; i<${#row}-1; i++)); do
        if [[ ${row:i:2} == PP ]]; then
          e=$i
          while (( e < ${#row} )) && [[ ${row:e:1} == P ]]; do e=$((e+1)); done
          arow=$r; ac=$(( i + (e - i) / 2 )); break 2
        fi
      done
    done
  fi
  (( arow < 0 )) && { arow=$(( er + 2 )); ac=$eyeC; }

  # never paint past the last body row: pix_trim was measured on the
  # authored grid, so anything hung below it gets sliced off at render
  local last=$(( ${#G[@]} - 1 ))
  while (( last > 0 )) && [[ ${G[last]} != *[!.]* ]]; do last=$((last-1)); done

  # mustache: two pixels either side of the mouth, at the anchor row — the
  # mouth cells between them stay clear, so the beard rings the mouth
  local brow x
  brow=${G[arow]}
  for x in $((ac - 3)) $((ac - 2)) $((ac + 1)) $((ac + 2)); do
    (( x < 0 || x >= ${#brow} )) && continue
    brow="${brow:0:x}B${brow:x+1}"
  done
  G[arow]=$brow

  # the beard hangs below the anchor, centered on it, tapering by tier;
  # widths mirror the mockup's 8→6→4 (grand-elder forks to 2)
  local -a widths
  case $blen in
    1) widths=(6 4) ;;
    2) widths=(8 6 4) ;;
    *) widths=(8 6 4) ;;
  esac
  local w bs be
  for ((i=0; i<${#widths[@]}; i++)); do
    w=${widths[i]}
    j=$(( arow + 1 + i ))
    (( j > last )) && break
    bs=$(( ac - w / 2 )); be=$(( ac + w / 2 - 1 ))
    brow=${G[j]}
    for ((x=bs; x<=be; x++)); do
      (( x < 0 || x >= ${#brow} )) && continue
      brow="${brow:0:x}B${brow:x+1}"
    done
    G[j]=$brow
  done
  # grand-elder (tier 3): a forked tip a row further down
  if (( blen >= 3 )); then
    j=$(( arow + 1 + ${#widths[@]} ))
    if (( j <= last )); then
      brow=${G[j]}
      for x in $((ac - 2)) $((ac + 1)); do
        (( x < 0 || x >= ${#brow} )) && continue
        brow="${brow:0:x}B${brow:x+1}"
      done
      G[j]=$brow
    fi
  fi
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

# the reading pose (curiosity ≥ 75, gitagotchi-reading.html): the pet holds an
# open book and turns the pages. Procedural like every other idle — the eyes go
# downcast, then a 10×4 book (reserved letters J cover / L bright page / Q dim
# page, K paws) is stamped IN FRONT of the lower body, centered under the face.
# pageframe 0 = book open & still · 1 = the right leaf lifts · 2 = it flips left.
pix_apply_reading() { # nameref grid, pageframe (0/1/2)
  local -n RG=$1
  local pf=$2
  local H=${#RG[@]} ri
  # geometry BEFORE the eyes go downcast, so the eye row is still findable
  local eyeRow=-1
  for ((ri=0; ri<H; ri++)); do
    [[ ${RG[ri]} == *KW* || ${RG[ri]} == *WK* ]] && { eyeRow=$ri; break; }
  done
  (( eyeRow < 0 )) && eyeRow=6
  # lowest body row + the body's center below the eyes (where the book rests)
  local lowRow=0 cLeft=99 cRight=0 r c first last
  for ((r=0; r<H; r++)); do
    [[ ${RG[r]} == *[!.]* ]] || continue
    lowRow=$r
    (( r > eyeRow )) || continue
    first=-1 last=-1
    for ((c=0; c<${#RG[r]}; c++)); do
      [[ ${RG[r]:c:1} != . ]] && { (( first < 0 )) && first=$c; last=$c; }
    done
    (( first >= 0 && first < cLeft )) && cLeft=$first
    (( last > cRight )) && cRight=$last
  done
  local cx=12
  (( cLeft <= cRight )) && cx=$(( (cLeft + cRight) / 2 ))
  # downcast eyes: the pupil drops toward the page (KW→DK, WK→KD)
  for ((ri=0; ri<H; ri++)); do
    local rr=${RG[ri]}
    rr=${rr//KW/DK}; rr=${rr//WK/KD}
    RG[ri]=$rr
  done
  # paint one cell in front of the body (the book overwrites what it covers)
  _bkput() { # row col letter
    local rw=$1 cc=$2 lt=$3
    (( rw < 0 || rw >= H || cc < 0 )) && return
    local s=${RG[rw]}
    (( cc >= ${#s} )) && return
    RG[rw]="${s:0:cc}${lt}${s:cc+1}"
  }
  # the book: 10 wide, 3 page rows over 1 cover row, centered under the face,
  # resting near the feet (but never off the bottom of the grid)
  local bw=10 mid=5 top left row x gx col
  top=$(( eyeRow + 3 )); (( lowRow - 3 > top )) && top=$(( lowRow - 3 ))
  (( top > H - 4 )) && top=$(( H - 4 ))
  left=$(( cx - 5 ))
  # the book's bottom row — pix_render widens its trim window to it, so a
  # short-bodied reader (the caterpillar) doesn't get the book sliced off
  READ_BOTTOM=$(( top + 3 ))
  for ((x=0; x<bw; x++)); do _bkput $((top + 3)) $((left + x)) J; done   # cover
  for ((row=0; row<3; row++)); do
    for ((x=0; x<bw; x++)); do
      gx=$(( left + x ))
      if (( x == mid )); then col=J                       # spine
      elif (( x < mid )); then                            # left leaf (static)
        col=L; (( row == 0 )) && col=Q
      else                                                # right leaf (animates)
        if [[ $pf == 1 ]] && (( x > mid + 1 && row < 2 )); then continue; fi   # lifting
        if [[ $pf == 2 ]] && (( x > mid && row < 2 )); then col=Q              # flipping
        else col=L; (( row == 0 )) && col=Q; fi
      fi
      _bkput $((top + row)) "$gx" "$col"
    done
  done
  # the turning leaf arcs across on the page-turn frames
  if [[ $pf == 1 ]]; then for r in 0 1 2; do _bkput $((top + r - 1)) $((cx + 2)) L; done; fi
  if [[ $pf == 2 ]]; then for r in 0 1 2; do _bkput $((top + r - 1)) $((cx - 1)) L; done; fi
  # little paws on the cover corners, holding it
  _bkput $((top + 2)) $((left - 1)) K
  _bkput $((top + 2)) $((left + bw)) K
}

# the guardian pose (outbound reviews ≥ 3, gitagotchi-spear.html): a full-
# height spear planted just outside the body on the given side, a leaf-blade
# steel head + red binding above the head, a gripping paw at mid-body, and a
# determined brow over the eyes. Procedural from geometry, so a tall penguin
# grips high and a low blob grips low. On the guard-tap frame the whole spear
# drops 1px and dust puffs at its base. Exports SPEAR_TOP/SPEAR_BOT so
# pix_render can widen its trim window to the blade tip and the butt.
SPEAR_TOP=0 SPEAR_BOT=0
pix_apply_spear() { # nameref grid, side (1 right / -1 left), tap (0/1)
  local -n SG=$1
  local side=$2 tap=$3
  local H=${#SG[@]} W=${#SG[0]} ri
  # eye row + eye columns (for the brow), then the body's bounding box
  local eyeRow=-1
  local -a eyeCols=()
  for ((ri=0; ri<H; ri++)); do
    local rr=${SG[ri]} i=0
    while (( i < ${#rr} - 1 )); do
      if [[ ${rr:i:2} == KW || ${rr:i:2} == WK ]]; then
        eyeCols+=("$i"); (( eyeRow < 0 )) && eyeRow=$ri; i=$((i + 2))
      else i=$((i + 1)); fi
    done
    (( eyeRow >= 0 )) && break
  done
  (( eyeRow < 0 )) && eyeRow=6
  local top=99 bot=0 left=99 right=0 c
  for ((ri=0; ri<H; ri++)); do
    [[ ${SG[ri]} == *[!.]* ]] || continue
    (( ri < top )) && top=$ri; (( ri > bot )) && bot=$ri
    local rr=${SG[ri]}
    for ((c=0; c<${#rr}; c++)); do
      [[ ${rr:c:1} != . ]] && { (( c < left )) && left=$c; (( c > right )) && right=$c; }
    done
  done
  local dy=0; (( tap )) && dy=1
  local sx groundY tipY
  if (( side > 0 )); then sx=$(( right + 2 )); (( sx > W - 2 )) && sx=$(( W - 2 ))
  else sx=$(( left - 2 )); (( sx < 1 )) && sx=1; fi
  groundY=$(( bot + 1 ))
  tipY=$(( top - 3 )); (( tipY < 0 )) && tipY=0
  _spput() { local y=$1 x=$2 lt=$3
    (( y < 0 || y >= H || x < 0 || x >= W )) && return
    local s=${SG[y]}; SG[y]="${s:0:x}${lt}${s:x+1}"; }
  # shaft below the head — a striped wooden pole down to the feet
  local y wc
  for ((y=tipY + 4; y<=groundY; y++)); do
    wc=Z; (( y % 2 )) && wc=Y
    _spput $((y + dy)) "$sx" "$wc"
  done
  # leaf-blade head: point, upper blade, shoulders, neck, then the red binding
  _spput $((tipY + dy)) "$sx" X
  _spput $((tipY + 1 + dy)) "$sx" X
  _spput $((tipY + 2 + dy)) $((sx - 1)) V; _spput $((tipY + 2 + dy)) "$sx" X; _spput $((tipY + 2 + dy)) $((sx + 1)) V
  _spput $((tipY + 3 + dy)) "$sx" V
  _spput $((tipY + 4 + dy)) "$sx" T
  # the gripping paw reaches from mid-body out to the shaft
  local gripY=$(( (eyeRow + bot) / 2 + 1 )) inner=$(( sx - side ))
  _spput $((gripY + dy)) "$sx" K            # knuckles on the shaft
  _spput $((gripY + dy)) "$inner" K         # paw outline
  _spput $((gripY + dy)) $(( inner - side )) O   # paw fill = body color
  # the determined brow: a dark bar over each eye
  local bc
  for bc in "${eyeCols[@]}"; do
    _spput $((eyeRow - 1)) "$bc" K
    _spput $((eyeRow - 1)) $((bc + 1)) K
  done
  # dust puffs when the butt taps the ground
  if (( tap )); then
    _spput $((groundY + 2)) $((sx - 1)) H
    _spput $((groundY + 2)) $((sx + 1)) H
  fi
  SPEAR_TOP=$(( tipY + dy )); SPEAR_BOT=$(( groundY + 2 ))
}

# the goodbye wave (§5.9, gitagotchi-goodbye_1.html): a raised forearm on the
# pet's outer edge, lifted above the head and swinging between two positions —
# the same procedural limb as the spear grip, just held high and flicked. From
# geometry, so a tall pet waves high and a low blob waves low. Body-colored fill
# (O) with a dark knuckle cap (K), like the spear's gripping paw. swing<0 holds
# the paw in and low, swing>0 throws it out and up; the goodbye alternates the
# two. Exports WAVE_TOP so pix_render widens its trim window to the lifted paw.
WAVE_TOP=0
pix_apply_wave() { # nameref grid, side (1 right / -1 left), swing (-1/1)
  local -n WG=$1
  local side=$2 swing=$3
  local H=${#WG[@]} W=${#WG[0]} ri c
  # eye row (the shoulder rides at eye height) and the body's topmost row
  local eyeRow=-1
  for ((ri=0; ri<H; ri++)); do
    if [[ ${WG[ri]} == *KW* || ${WG[ri]} == *WK* ]]; then eyeRow=$ri; break; fi
  done
  (( eyeRow < 0 )) && eyeRow=6
  local top=99
  for ((ri=0; ri<H; ri++)); do [[ ${WG[ri]} == *[!.]* ]] && { top=$ri; break; }; done
  (( top > 90 )) && top=0
  _wvput() { local y=$1 x=$2 lt=$3
    (( y < 0 || y >= H || x < 0 || x >= W )) && return
    local s=${WG[y]}; WG[y]="${s:0:x}${lt}${s:x+1}"; }
  # shoulder: just past the body's own edge on the eye row, so the arm grows
  # out of the body rather than floating at the grid margin (a tail or frill
  # that juts further down never drags the shoulder out with it)
  local sy=$eyeRow shoX=-1 rr=${WG[eyeRow]}
  if (( side > 0 )); then
    for ((c=${#rr}-1; c>=0; c--)); do [[ ${rr:c:1} != . ]] && { shoX=$c; break; }; done
    shoX=$(( shoX + 1 ))
  else
    for ((c=0; c<${#rr}; c++)); do [[ ${rr:c:1} != . ]] && { shoX=$c; break; }; done
    shoX=$(( shoX - 1 ))
  fi
  (( shoX < 0 )) && shoX=0; (( shoX > W - 1 )) && shoX=$(( W - 1 ))
  # the raised paw sits above the head; the +swing beat throws it a column
  # further out and a row higher — the flick that reads as the wave
  local tipY=$(( top - 1 + (swing > 0 ? 0 : 1) )); (( tipY < 0 )) && tipY=0
  local reach=$(( 2 + (swing > 0 ? 1 : 0) ))
  local tipX=$(( shoX + side * reach ))
  (( tipX < 0 )) && tipX=0; (( tipX > W - 1 )) && tipX=$(( W - 1 ))
  # the forearm: a straight limb from shoulder to paw, stepped along the long
  # axis so it stays connected at every intermediate row
  local dx=$(( tipX - shoX )) dy=$(( tipY - sy ))
  local adx=${dx#-} ady=${dy#-} steps x y i
  steps=$(( adx > ady ? adx : ady )); (( steps == 0 )) && steps=1
  for ((i=0; i<=steps; i++)); do
    x=$(( shoX + dx * i / steps )); y=$(( sy + dy * i / steps ))
    _wvput "$y" "$x" O
  done
  # the paw at the tip (two rows tall) with a dark knuckle cap above it
  _wvput "$tipY" "$tipX" O
  _wvput $(( tipY + 1 )) "$tipX" O
  _wvput $(( tipY - 1 )) "$tipX" K
  WAVE_TOP=$(( tipY - 1 )); (( WAVE_TOP < 0 )) && WAVE_TOP=0
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
  local id=$1 frame=$2 blink=$3 specs=${4:-0} tired=${5:-0} flip=${6:-0} body=${7:-0} mood=${8:-0} sixp=${9:-0} bigeye=${10:-0} brows=${11:-0} wag=${12:-0} beard=${13:-0} gurney=${14:-0} spear=${15:-0} reading=${16:-} wave=${17:-0}
  # ASCII-era frame names → pixel two-frame names
  case $frame in
    sick) frame=sick_1 ;; celebrate) frame=celebrate_1 ;;
    belly|stretch|young) frame=idle_1 ;;
  esac
  [[ -n ${PIXF[$id/$frame]:-} ]] || frame=idle_1
  # the cocoon hides the body — hibernation shape stays canonical
  [[ $frame == hibernate_* ]] && body=0
  # sick, sleeping and cocooned faces carry their own expression — and none
  # of them stands guard: the spear waits by the door, the book stays shut
  [[ $frame == sick_* || $frame == sleep_* || $frame == hibernate_* ]] && { mood=0 bigeye=0 brows=0 wag=0 spear=0 reading="" wave=0; }
  # a waving paw can't also grip the spear — the goodbye wave wins the arm
  (( wave != 0 )) && spear=0
  # the cocoon hides the chin too (the beard survives sleep — it's earned)
  [[ $frame == hibernate_* ]] && beard=0
  # dilation and brows are invisible behind elder spectacle rims
  [[ $specs == 1 ]] && bigeye=0 brows=0
  local ck="$id/$frame/$blink/$specs/$tired/$flip/$body/$mood/$sixp/$bigeye/$brows/$wag/$beard/$gurney/$spear/$reading/$wave/$PC_KEY/$PIX_MODE"
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
  [[ -n $reading ]] && pix_apply_reading g "$reading"
  (( wag == 1 )) && pix_apply_wag g 1
  if (( spear != 0 )); then
    # the guardian pose: planted beside the body, gripped mid-shaft, brow set
    # (pix_apply_spear, from geometry). Placed on the right; the flip below
    # mirrors it for a facing friend. spear==2 is the guard-tap beat. After
    # wag (a planted spear doesn't swish), before flip.
    pix_apply_spear g 1 "$(( spear == 2 ? 1 : 0 ))"
  fi
  if (( wave != 0 )); then
    # the goodbye wave: a raised paw on the right edge, swung by the sign of
    # `wave` (pix_apply_wave, from geometry). Placed like the spear so a flip
    # mirrors it for a facing render; after wag, before flip.
    pix_apply_wave g 1 "$wave"
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
  if (( spear != 0 )); then
    # the blade rises above the head and the butt + dust drop below the feet —
    # widen the window both ways (kept even top / odd bottom for half-blocks)
    (( SPEAR_TOP < r0 )) && { r0=$SPEAR_TOP; (( r0 % 2 )) && r0=$(( r0 - 1 )); (( r0 < 0 )) && r0=0; }
    (( SPEAR_BOT > r1 )) && { r1=$SPEAR_BOT; (( r1 % 2 == 0 )) && r1=$(( r1 + 1 )); (( r1 >= ${#g[@]} )) && r1=$(( ${#g[@]} - 1 )); }
  fi
  if (( wave != 0 )); then
    # the lifted paw rises above the head — widen the window up (kept even for
    # the half-block pairing) so the wave isn't sliced off at the top
    (( WAVE_TOP < r0 )) && { r0=$WAVE_TOP; (( r0 % 2 )) && r0=$(( r0 - 1 )); (( r0 < 0 )) && r0=0; }
  fi
  if [[ -n $reading ]] && (( ${READ_BOTTOM:-0} > r1 )); then
    # the held book can hang below a short pet's feet — widen the window down
    # (kept odd for the half-block pairing) so the cover isn't sliced off
    r1=$READ_BOTTOM; (( r1 % 2 == 0 )) && r1=$(( r1 + 1 ))
    (( r1 >= ${#g[@]} )) && r1=$(( ${#g[@]} - 1 ))
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
