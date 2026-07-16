# gitagotchi — lib/util.sh
# glyph tiers, ANSI-256 color math, linguist colors, seed derivation, name generator.
# Everything here is a pure function of its inputs (plan.md §1).

VERSION="1.0.7"

die() { printf 'gh-pet: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# same_login a b — GitHub logins are case-insensitive, so every comparison of
# one against another must be too: the CLI arg and the PRETEND_* knobs carry
# whatever casing was typed, while API payloads carry the canonical spelling.
# An empty side never matches (unauthenticated ME, unset knob) — `gh-pet ""`
# is not everyone. stats.jq holds the jq-side twin of this rule.
same_login() { [[ -n $1 && -n $2 && ${1,,} == "${2,,}" ]]; }

# ── glyph tiers (design.md §2.1) ────────────────────────────────────────────
# Tier B (common unicode) is default on UTF-8 terminals; --ascii forces tier A.
init_glyphs() { # $1 = "A" or "B"
  TIER=$1
  if [[ $TIER == B ]]; then
    G_MAIL="✉" G_SCROLL="⎘" G_HEART="❤" G_HEART_FLOAT="♥" G_ZZZ="💤"
    G_FILL="█" G_EMPTY="░" G_HORIZ="·" G_FROZEN="❄" G_NOTCH="¦"
    G_SPOT1="•" G_SPOT2="∘" G_STRIPE="≋" G_PATCH="▒"
    G_FLY1=".·°" G_FLY2="°·." G_BALL="●" G_SPARK="✦" G_THERMO="▍"
    G_MOON="☾" G_FLOWER="❀" G_LEAF="∘"
    G_ACC_BANDANA="«▼»" G_ACC_BOWTIE="»◊«" G_ACC_COLLAR="–⊙–" G_ACC_CROWN=".^."
    G_SEL="▸" G_CMPW="◂" G_DOT_OK="✓" G_DOT_NONE="◦" G_SPIN="⟳" G_WAIT="⌛"
    B_TL="┌" B_TR="┐" B_BL="└" B_BR="┘" B_H="─" B_V="│"
  else
    G_MAIL="M" G_SCROLL="R" G_HEART="<3" G_HEART_FLOAT="v" G_ZZZ="zZ"
    G_FILL="#" G_EMPTY="-" G_HORIZ="." G_FROZEN="*" G_NOTCH="|"
    G_SPOT1="o" G_SPOT2="." G_STRIPE="=" G_PATCH="%"
    G_FLY1=".oO" G_FLY2="Oo." G_BALL="o" G_SPARK="*" G_THERMO="|="
    G_MOON="C" G_FLOWER="*" G_LEAF="o"
    G_ACC_BANDANA="<v>" G_ACC_BOWTIE=">o<" G_ACC_COLLAR="-o-" G_ACC_CROWN=".^."
    G_SEL=">" G_CMPW="<" G_DOT_OK="+" G_DOT_NONE="o" G_SPIN="~" G_WAIT="%"
    B_TL="+" B_TR="+" B_BL="+" B_BR="+" B_H="-" B_V="|"
  fi
}

detect_tier() {
  [[ ${OPT_ASCII:-0} == 1 ]] && { echo A; return; }
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) echo B ;;
    *) echo A ;;
  esac
}

# ── day/night + seasons (plan.md §11, unparked) ─────────────────────────────
# The scene is the wall_clock half of pet_state = f(github_data, wall_clock):
# derived fresh every frame, nothing stored. Knobs pin it for snapshots and
# previews: GITAGOTCHI_PRETEND_HOUR=<0-23>, GITAGOTCHI_PRETEND_MONTH=<1-12>,
# GITAGOTCHI_HEMI=S (southern hemisphere flips the seasons, not the clock).
SCENE_NIGHT=0 SCENE_SEASON=summer
scene_calc() {
  local hm; printf -v hm '%(%H %m)T' -1
  local hour=$(( 10#${hm%% *} ))
  local month=$(( 10#${hm##* } ))
  hour=${GITAGOTCHI_PRETEND_HOUR:-$hour}
  month=${GITAGOTCHI_PRETEND_MONTH:-$month}
  SCENE_NIGHT=0
  (( hour >= 20 || hour < 6 )) && SCENE_NIGHT=1
  [[ ${GITAGOTCHI_HEMI:-N} == [Ss]* ]] && month=$(( (month + 5) % 12 + 1 ))
  case $month in
    12|1|2) SCENE_SEASON=winter ;;
    3|4|5)  SCENE_SEASON=spring ;;
    6|7|8)  SCENE_SEASON=summer ;;
    *)      SCENE_SEASON=autumn ;;
  esac
  # the night tint reaches the pixel palette (pix_palette cache key)
  PIX_NIGHT=$SCENE_NIGHT
}

moonlit() { # "r;g;b" → MLIT: the same shade under moonlight (cool + dim);
  local rgb=$1        # bash twin of pix_palette's awk dimc night factors
  local r=${rgb%%;*} rest=${rgb#*;}
  local g=${rest%%;*}
  local b=${rest#*;}
  MLIT="$(( r * 70 / 100 ));$(( g * 75 / 100 ));$(( b * 92 / 100 ))"
}

# ── SGR helpers (color roles, design.md §2.2) ───────────────────────────────
ESC=$'\e'
RS=$'\e[0m'
fg() { printf '\e[38;5;%sm' "$1"; }
C_CHROME=$(fg 240)   # borders, labels — recedes
C_INK=$'\e[39m'
C_VOICE=$(fg 250)$'\e[3m'   # pet-voice line: 250, italic
C_TRACK=$(fg 238)    # empty bar track
C_RED=$(fg 196) C_AMBER=$(fg 214) C_GREEN=$(fg 77)
C_HEARTS=$(fg 204)   # happiness hearts, soft red
C_MAILC=$(fg 221)    # mail envelope — attention without alarm
C_SCROLLC=$(fg 45)   # review scroll — "work" color
C_SECWARN=$(fg 203)  # security pre-warning
C_ICE=$(fg 117)      # hibernation / frozen
C_DIM=$'\e[2m' C_BOLD=$'\e[1m' C_ITAL=$'\e[3m'
C_ACC=$(fg 45)       # accessory tint

bar_color() { # value → stat-bar fill color (ramp per §2.2)
  local v=$1
  if (( v < 20 )); then printf '%s' "$C_RED"
  elif (( v < 50 )); then printf '%s' "$C_AMBER"
  else printf '%s' "$C_GREEN"; fi
}

# OSC 8 hyperlink; falls back to plain text when disabled
osc8() { # url text
  if [[ ${OPT_NOLINKS:-0} == 1 || -z $1 ]]; then printf '%s' "$2"
  else printf '\e]8;;%s\e\\%s\e]8;;\e\\' "$1" "$2"; fi
}

# ── ANSI-256 nearest-color mapping ──────────────────────────────────────────
hex_to_256() { # "#rrggbb" → nearest xterm-256 index
  local hex=${1#\#} r g b
  r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
  local levels=(0 95 135 175 215 255) best_i=0 best_d=99999999
  # 6×6×6 cube
  local ri gi bi i d dr dg db
  for ri in 0 1 2 3 4 5; do for gi in 0 1 2 3 4 5; do for bi in 0 1 2 3 4 5; do
    dr=$((r - levels[ri])); dg=$((g - levels[gi])); db=$((b - levels[bi]))
    d=$((dr*dr + dg*dg + db*db))
    if (( d < best_d )); then best_d=$d; best_i=$((16 + 36*ri + 6*gi + bi)); fi
  done; done; done
  # grayscale ramp 232..255
  local gray gv
  for i in $(seq 0 23); do
    gv=$((8 + i*10)); dr=$((r-gv)); dg=$((g-gv)); db=$((b-gv))
    d=$((dr*dr + dg*dg + db*db))
    if (( d < best_d )); then best_d=$d; best_i=$((232 + i)); fi
  done
  printf '%s' "$best_i"
}

# ── linguist colors (official hexes; subset bundled) ────────────────────────
declare -A LINGUIST=(
  [Python]="#3572A5" [JavaScript]="#F1E05A" [TypeScript]="#3178C6" [Rust]="#DEA584"
  [Go]="#00ADD8" [Ruby]="#701516" [Java]="#B07219" [C]="#555555" [C++]="#F34B7D"
  [C#]="#178600" [PHP]="#4F5D95" [Swift]="#F05138" [Kotlin]="#A97BFF" [Shell]="#89E051"
  [HTML]="#E34C26" [CSS]="#663399" [SCSS]="#C6538C" [Haskell]="#5E5086" [Elixir]="#6E4A7E"
  [Erlang]="#B83998" [Clojure]="#DB5855" [Scala]="#C22D40" [Lua]="#000080" [Perl]="#0298C3"
  [R]="#198CE7" [Julia]="#A270BA" [Dart]="#00B4AB" [Zig]="#EC915C" [Nim]="#FFC200"
  [OCaml]="#EF7A08" [F#]="#B845FC" [Dockerfile]="#384D54" [Makefile]="#427819"
  [TeX]="#3D6117" [Vue]="#41B883" [Svelte]="#FF3E00" [Objective-C]="#438EFF"
  [Assembly]="#6E4C13" [PowerShell]="#012456" [Groovy]="#4298B8" [Crystal]="#000100"
  [Solidity]="#AA6746" [MATLAB]="#E16737" [Vim Script]="#199F4B" [Emacs Lisp]="#C065DB"
  ["Jupyter Notebook"]="#DA5B0B" [Astro]="#FF5A03" [Nix]="#7E7EFF" [Terraform]="#844FBA"
  [HCL]="#844FBA" [Elm]="#60B5CC" [Gleam]="#FFAFF3" [V]="#4F87C4" [D]="#BA595E"
)
# fallback palette for users with no repos: seed[7] → one of these (plan.md §2)
FALLBACK_PALETTE=("#DEA584" "#3572A5" "#F1E05A" "#41B883" "#BC8CF2" "#F778BA" "#79C0F2" "#89E051")

# ── identity seed (plan.md §2): seed = sha256(user.id) ──────────────────────
declare -a SEED
seed_init() { # $1 = numeric user id
  local hex
  if have shasum; then hex=$(printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1)
  else hex=$(printf '%s' "$1" | sha256sum | cut -d' ' -f1); fi
  SEED=()
  local i
  for ((i=0; i<32; i++)); do SEED[i]=$((16#${hex:i*2:2})); done
}

# hsl → "r;g;b", integer math ×1000 (bash has no floats). The awk twin inside
# pix_palette hue-shifts the pelt; this one exists because the beard is dyed in
# bash, before any palette runs.
hsl_rgb() { # h 0-359 · s 0-100 · l 0-100
  local h=$1 c x m r g b
  local L=$(( $3 * 10 )) S=$(( $2 * 10 ))
  local d=$(( 2 * L - 1000 )); (( d < 0 )) && d=$(( -d ))
  c=$(( (1000 - d) * S / 1000 ))
  local t=$(( (h * 1000 / 60) % 2000 ))
  local u=$(( t - 1000 )); (( u < 0 )) && u=$(( -u ))
  x=$(( c * (1000 - u) / 1000 ))
  m=$(( L - c / 2 ))
  case $(( h / 60 )) in
    0) r=$c; g=$x; b=0  ;;
    1) r=$x; g=$c; b=0  ;;
    2) r=0;  g=$c; b=$x ;;
    3) r=0;  g=$x; b=$c ;;
    4) r=$x; g=0;  b=$c ;;
    *) r=$c; g=0;  b=$x ;;
  esac
  printf '%s;%s;%s' $(( (r + m) * 255 / 1000 )) $(( (g + m) * 255 / 1000 )) \
                    $(( (b + m) * 255 / 1000 ))
}

# rgb → hue 0-359, or -1 for an achromatic shade (the grey coats: C #555555,
# Crystal #000100). Integer math, same reason as hsl_rgb.
rgb_hue() { # "r;g;b"
  # split the declarations — `local rest=… g=${rest…}` expands rest BEFORE it is
  # assigned (the trap this codebase keeps re-learning; moonlit above splits for
  # the same reason). Under set -u it errored and silently returned a junk hue.
  local rgb=$1
  local r=${rgb%%;*} rest=${rgb#*;}
  local g=${rest%%;*}
  local b=${rest#*;}
  local mx=$r mn=$r
  (( g > mx )) && mx=$g; (( b > mx )) && mx=$b
  (( g < mn )) && mn=$g; (( b < mn )) && mn=$b
  local d=$(( mx - mn ))
  (( d < 12 )) && { printf -- '-1'; return; }   # too little chroma to have a hue
  local h
  if   (( mx == r )); then h=$(( (60 * (g - b) / d + 360) % 360 ))
  elif (( mx == g )); then h=$(( 60 * (b - r) / d + 120 ))
  else                     h=$(( 60 * (r - g) / d + 240 )); fi
  printf '%s' $(( (h + 360) % 360 ))
}

# beard shade (plan.md §2): an identity trait, sha256 of the account's CREATED
# timestamp AND its numeric id. The id is what makes it UNIQUE: created_at alone
# collides (two accounts signing up the same second share a beard), and stats.jq
# substitutes one CONSTANT date whenever user.json hasn't landed, which dyed
# every such pet the same shade.
#
# The hue is the FULL circle, not a natural-hair gamut: this is dyed hair, not
# greying. The old version quantized to ten shades, of which silver/snow/ash all
# read as one pale grey and chestnut/dark-brown/black as one near-black — four
# perceptual families, so any four pets on a stage were a coin flip to wear the
# same beard (they did: wjames111 and canac both hashed to chestnut).
#
# ██ The hue is an OFFSET FROM THE COAT, never an absolute. ██ A free-running
# hue eventually lands on the pet's own color and the beard disappears into the
# face: canac's blue hamster wore a blue beard at a redmean distance of 31 —
# invisible. So identity picks a rotation of 90°–270° AWAY from the coat's hue,
# which cannot land within 90° of it. The coat's hue is the LINGUIST hue: the
# pelt is the species palette hue-shifted onto it, and the rendered O comes out
# within 1° of the language's own hue on all 50 species (measured), so the hex
# is a faithful stand-in for what actually gets drawn. An achromatic coat (C's
# #555555) has no hue to run from — a saturated beard already contrasts with
# grey — so identity takes the whole circle there.
#
# THE TRADE: the beard now moves if your TOP LANGUAGE changes. It cannot both
# be immutable and be guaranteed to contrast a coat that itself changes color —
# contrast has to depend on the coat. The RELATIONSHIP is the immutable part:
# your rotation away from your coat is yours forever.
#
# Saturation floors at 55 so no shade washes out to grey; lightness stays in
# 40-62 so it survives BOTH the ×0.45 faint dim and the night moonlit() pass.
#
# ██ PINNED, like gen_name — nothing is stored, so a pet's beard exists ONLY as
# this mapping. Any edit here re-dyes every beard in the wild. Version it,
# don't tune it in place.
beard_color_for() { # $1 = CREATED iso · $2 = numeric user id · $3 = coat hex
  local src="$1:${2:-0}" hex
  if have shasum; then hex=$(printf '%s' "$src" | shasum -a 256 | cut -d' ' -f1)
  else hex=$(printf '%s' "$src" | sha256sum | cut -d' ' -f1); fi
  local coat=${3#\#} coathue=-1
  [[ $coat =~ ^[0-9A-Fa-f]{6}$ ]] && \
    coathue=$(rgb_hue "$((16#${coat:0:2}));$((16#${coat:2:2}));$((16#${coat:4:2}))")
  local hue
  if (( coathue < 0 )); then hue=$(( 16#${hex:0:4} % 360 ))
  else hue=$(( (coathue + 90 + 16#${hex:0:4} % 181) % 360 )); fi
  hsl_rgb "$hue" $(( 55 + 16#${hex:4:2} % 31 )) $(( 40 + 16#${hex:6:2} % 23 ))
}

# name generator (plan.md §2.1) — a pet's name should sound like something you
# would call across a room, so the sounds are picked for softness: no spiky
# onset clusters (kr/vr/zh/st/th/gr/dr/pr all cut), finals weighted to o/i/u,
# and a coda that is usually nothing at all — an open vowel is what keeps a
# name round. A quarter of pets echo their first syllable (Memeku, Chochowi);
# reduplication is the oldest cuteness trick there is.
#
# ~2×10⁷ names are reachable, but that count is not the number that matters.
# The arrays are deliberately weighted and the 8-letter cap keeps most names at
# two syllables, so names are nowhere near uniform: measured, two random pets
# share a name about 1 in 60k. The echo accounts for nearly all of that — with
# it switched off the softer arrays actually beat the old spiky ones (1 in 1M
# vs 1 in 800k), so it is the reduplication, not the softness, that is bought
# here. In a 40-friend list that is a ~1.3% chance of a twin, and a twin is
# charming rather than broken — two real pets can share a name too.
#
# ██ FROZEN — do not edit the arrays or the indexing below. ██
# "Same account, same name, forever" is a promise to the user: nothing is
# stored, so the name exists ONLY as this mapping — any change (even
# reordering an array) silently renames every pet in the wild. The suite
# pins id 3151702 → "Chochowi"; if a change here is ever truly unavoidable,
# it must be versioned, not edited in place.
NAME_ONS=(b d f g h j k l m n p r s t v w y z bl ch fl pl sh)
NAME_VOWS=(a e i o u)
NAME_VOWF=(o i u o i u a e o i ai oi ia io u)   # o/i/u carry it; diphthongs spice
NAME_CODA=("" "" "" "" "" "" "" "" "" n m l n m l)   # usually open, never spiky
gen_name() {
  # names stay generally 8 letters or fewer: always two syllables, a third only
  # when it still fits, and a coda for spice on some seeds when there's room.
  # Built to fit rather than truncated, so no jarring cut-offs — and not a hard
  # cap, just a bias away from the old 11–17 letter mouthfuls.
  local name="" first="" i
  for ((i=0; i<3; i++)); do
    local ons=${NAME_ONS[SEED[2*i+2] % ${#NAME_ONS[@]}]} vow
    if (( i == 0 )); then vow=${NAME_VOWS[SEED[2*i+3] % ${#NAME_VOWS[@]}]}
    else vow=${NAME_VOWF[SEED[2*i+3] % ${#NAME_VOWF[@]}]}; fi
    local syl="$ons$vow"
    (( i == 1 && SEED[14] % 4 == 0 )) && syl=$first   # the echo (seed byte 14 is otherwise unused)
    (( i >= 2 && ${#name} + ${#syl} > 8 )) && break
    (( i == 0 )) && first=$syl
    name+="$syl"
  done
  local coda=${NAME_CODA[SEED[15] % ${#NAME_CODA[@]}]}
  (( ${#name} + ${#coda} <= 8 && SEED[16] % 2 == 0 )) && name+="$coda"
  printf '%s' "$(tr '[:lower:]' '[:upper:]' <<<"${name:0:1}")${name:1}"
}

# species: seed[0] % (bundled species count), list sorted for determinism
species_list() { ls "$SPRITE_DIR"/*.sprite 2>/dev/null | sed 's|.*/||; s|\.sprite$||' | sort; }
pick_species() {
  local -a all; mapfile -t all < <(species_list)
  (( ${#all[@]} )) || die "no sprites found in $SPRITE_DIR"
  printf '%s' "${all[SEED[0] % ${#all[@]}]}"
}

# pattern: second-most-used language bucket → solid/spots/stripes/patches (plan.md §2)
pattern_for_lang() { # $1 = second language name ("" → solid)
  [[ -z $1 ]] && { echo solid; return; }
  local sum=0 i c
  for ((i=0; i<${#1}; i++)); do c=$(printf '%d' "'${1:i:1}" 2>/dev/null || echo 0); sum=$((sum + c)); done
  case $((sum % 4)) in
    0) echo solid ;; 1) echo spots ;; 2) echo stripes ;; 3) echo patches ;;
  esac
}

# accessory precedence: crown > collar tag > bowtie > bandana > bare (plan.md §2, design.md §6.6)
pick_accessory() { # $1=site_admin/pro $2=org_member $3=hireable $4=bio_set
  if [[ $1 == true ]]; then echo crown
  elif [[ $2 == true ]]; then echo collar
  elif [[ $3 == true ]]; then echo bowtie
  elif [[ $4 == true ]]; then echo bandana
  else echo bare; fi
}

pet_color_hex() { # $1 = top language ("" → seed fallback)
  local lang=$1
  if [[ -n $lang && -n ${LINGUIST[$lang]:-} ]]; then printf '%s' "${LINGUIST[$lang]}"
  elif [[ -n $lang ]]; then printf '%s' "${FALLBACK_PALETTE[SEED[7] % 8]}"
  else printf '%s' "${FALLBACK_PALETTE[SEED[7] % 8]}"; fi
}

# ── misc ────────────────────────────────────────────────────────────────────
clampi() { local v=$1; (( v < $2 )) && v=$2; (( v > $3 )) && v=$3; printf '%s' "$v"; }

# Built by printf padding rather than a concat loop: this is called ~100×/frame
# (every pad, rule and gap), and appending one char at a time made it 76ms of a
# 420ms draw. `%*s` produces the run in one shot; the substitution swaps in the
# glyph. A count ≤ 0 must yield "" — the old loop simply didn't iterate.
repeat_str() { # char count
  (( $2 > 0 )) || return 0
  local out
  printf -v out '%*s' "$2" ''
  [[ $1 == " " ]] && { printf '%s' "$out"; return; }
  printf '%s' "${out// /$1}"
}

padw() { # string width — pad by CHARACTER count (printf %-Ns pads by bytes,
  local s=$1 w=$2                       # which breaks on ❤ ≼o≽ and friends)
  local need=$(( w - ${#s} ))
  (( need > 0 )) && s+=$(repeat_str " " "$need")
  printf '%s' "$s"
}

trunc() { # string maxlen → truncate with …
  local s=$1 max=$2
  if (( ${#s} > max )); then
    if [[ $TIER == B ]]; then printf '%s…' "${s:0:max-1}"
    else printf '%s...' "${s:0:max-3}"; fi
  else printf '%s' "$s"; fi
}

# marquee: text that doesn't fit slides across its slot instead of cutting off.
# Holds briefly at the start, scrolls 1 char per tick, holds at the end, loops.
# Driven by TICK — session-local animation, nothing persisted (plan.md §1).
marquee() { # string width [salt]
  local s=$1 w=$2 salt=${3:-0}
  local len=${#s}
  (( len <= w )) && { printf '%s' "$s"; return; }
  (( w < 1 )) && return
  local span=$(( len - w )) hold=6
  local total=$(( hold + span + hold ))
  local phase=$(( (${TICK:-0} + salt) % total ))
  local off=$(( phase - hold ))
  (( off < 0 )) && off=0
  (( off > span )) && off=$span
  printf '%s' "${s:off:w}"
}

# human "Ns/Nm/Nh" age
age_str() { # seconds
  local s=$1
  if (( s < 60 )); then printf '%ss' "$s"
  elif (( s < 3600 )); then printf '%sm' $((s/60))
  else printf '%sh' $((s/3600)); fi
}

# medal name → shelf code (plan.md §4)
medal_code() {
  case "$1" in
    "Pull Shark") echo PS ;; "YOLO") echo YOLO ;; "Quickdraw") echo QD ;;
    "Galaxy Brain") echo GB ;; "Pair Extraordinaire") echo PE ;; "Starstruck") echo SS ;;
    "Public Sponsor") echo SP ;; "Arctic Code Vault Contributor") echo ACV ;;
    "Mars 2020 Contributor") echo M20 ;; "Open Sourcerer") echo OS ;;
    "Heart On Your Sleeve") echo HS ;;
    *) printf '%s' "$(tr '[:lower:]' '[:upper:]' <<<"${1:0:2}")" ;;
  esac
}

sup_tier() { # ×N tier → superscript (tier B) or xN (tier A)
  (( $1 <= 1 )) && return
  if [[ $TIER == B ]]; then
    case $1 in 2) printf '²';; 3) printf '³';; 4) printf '⁴';; *) printf '×%s' "$1";; esac
  else printf 'x%s' "$1"; fi
}
