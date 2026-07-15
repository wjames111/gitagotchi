# gitagotchi — lib/dense.sh
# Dense mode (ux-spec §9, gitachis.html): btop's grammar — every region is a
# bordered box whose border color is its identity, title embedded ┤ so ├,
# hotkey pinned top-right. Default at ≥110×32 with truecolor; cozy (§5) is the
# fallback. Layout:
#   header: logo · @login · id · lang ─ [✉] [⎘] · api n/5000 · clock
#   ┤ pet ├ (linguist color)      ┤ vitals ├ (green)
#   ┤ activity · events/day · 60d ├ (contribution-green, full width)
#   ┤ friends ├ (blue)            ┤ feed ├ (purple)
#   footer: key buttons ─ ✓ synced

# palette (gitachis.html :root, truecolor)
RGB_GREEN="63;185;80"    RGB_ACT="57;211;83"    RGB_BLUE="88;166;255"
RGB_PURPLE="188;140;242" RGB_YELLOW="210;153;34" RGB_RED="248;81;73"
RGB_CYAN="57;197;207"    RGB_ICE="121;192;242"   RGB_ORANGE="240;136;62"
RGB_MUTED="139;148;158"  RGB_FAINT="72;79;88"    RGB_TRACK="33;38;45"
RGB_INK="230;237;243"    RGB_VOICE="179;186;194" RGB_PINK="247;120;186"
RGB_GROUND="44;52;64"    RGB_SEP="38;44;51"      # .ground #2c3440 · .vsep #262c33
ACT_G0="22;27;34" ACT_G1="14;68;41" ACT_G2="0;109;50" ACT_G3="38;166;65" ACT_G4="57;211;83"

fgt() { printf '\e[38;2;%sm' "$1"; }
hex_to_rgb() { local h=${1#\#}; printf '%d;%d;%d' $((16#${h:0:2})) $((16#${h:2:2})) $((16#${h:4:2})); }

dense_active() {
  # dense is the default at every size — the layout compresses instead of
  # refusing; cozy is opt-in via --cozy or the d key
  [[ ${DENSE_FORCE:-} != 0 ]]
}

# ── full-screen segment compositor (same skip-on-overlap rule as the stage) ─
declare -a DROW
scr_reset() { DROW=(); local i; for ((i=0; i<LINES; i++)); do DROW[i]=""; done; }
scr_put() { # row x len colored
  local row=$1 x=$2 len=$3
  (( row < 0 || row >= LINES )) && return
  (( x < 0 || x + len > COLS )) && return
  DROW[row]+="${x}${US}${len}${US}${4}${RSEP}"
}
scr_emit() {
  SCREEN=()
  local i seg x len str
  for ((i=0; i<LINES; i++)); do
    local out="" cursor=0
    local -a xs=() ls=() ss=()
    local IFS=$RSEP
    for seg in ${DROW[i]}; do
      [[ -z $seg ]] && continue
      IFS=$US read -r x len str <<<"$seg"
      xs+=("$x"); ls+=("$len"); ss+=("$str")
    done
    unset IFS
    local n=${#xs[@]} j
    while :; do
      local best=-1
      for ((j=0; j<n; j++)); do
        [[ -z ${xs[j]:-} ]] && continue
        if (( best == -1 || xs[j] < xs[best] )); then best=$j; fi
      done
      (( best == -1 )) && break
      x=${xs[best]}; len=${ls[best]}; str=${ss[best]}; unset "xs[best]"
      if (( x >= cursor )); then
        (( x > cursor )) && out+=$(repeat_str " " $((x - cursor)))
        out+="$str"; cursor=$((x + len))
      fi
    done
    SCREEN+=("$out")
  done
}

# screen_overlay row col glyph — the z-layer: splices a one-column colored
# glyph OVER the emitted SCREEN line at an absolute position. Walks visible
# columns (skipping SGR + OSC sequences), replaces exactly one cell, and
# re-applies the interrupted color state so the text underneath survives.
screen_overlay() { # row col colored_glyph [display_width]
  local row=$1 col=$2 g=$3 gw=${4:-1}
  (( row < 0 || row >= ${#SCREEN[@]} || col < 0 || col + gw > COLS )) && return
  local line=${SCREEN[row]}
  local out="" state="" vis=0 i=0 n=${#line}
  while (( i < n )); do
    local ch=${line:i:1}
    if [[ $ch == $'\e' ]]; then
      local nxt=${line:i+1:1}
      if [[ $nxt == "[" ]]; then
        local j=$((i + 2))
        while (( j < n )) && [[ ${line:j:1} != m ]]; do j=$((j + 1)); done
        local seq=${line:i:j-i+1}
        if [[ $seq == $'\e[0m' ]]; then state=""; else state+=$seq; fi
        out+=$seq
        i=$((j + 1))
        continue
      elif [[ $nxt == "]" ]]; then
        local j=$((i + 2))
        while (( j + 1 < n )) && ! [[ ${line:j:1} == $'\e' && ${line:j+1:1} == "\\" ]]; do j=$((j + 1)); done
        out+=${line:i:j-i+2}
        i=$((j + 2))
        continue
      fi
    fi
    if (( vis == col )); then
      out+=$'\e[0m'"${g}"$'\e[0m'
      # consume gw underlying columns (a 2-col emoji eats two), keeping any
      # color state and hyperlink sequences they carried
      local left=$gw
      while (( i < n && left > 0 )); do
        ch=${line:i:1}
        if [[ $ch == $'\e' ]]; then
          local nxt2=${line:i+1:1}
          if [[ $nxt2 == "[" ]]; then
            local j2=$((i + 2))
            while (( j2 < n )) && [[ ${line:j2:1} != m ]]; do j2=$((j2 + 1)); done
            local seq2=${line:i:j2-i+1}
            if [[ $seq2 == $'\e[0m' ]]; then state=""; else state+=$seq2; fi
            i=$((j2 + 1))
            continue
          elif [[ $nxt2 == "]" ]]; then
            local j2=$((i + 2))
            while (( j2 + 1 < n )) && ! [[ ${line:j2:1} == $'\e' && ${line:j2+1:1} == "\\" ]]; do j2=$((j2 + 1)); done
            out+=${line:i:j2-i+2}
            i=$((j2 + 2))
            continue
          fi
        fi
        i=$((i + 1)); left=$((left - 1))
      done
      out+="${state}${line:i}"
      SCREEN[row]=$out
      return
    fi
    out+=$ch
    i=$((i + 1)); vis=$((vis + 1))
  done
  # the row ends before the column — pad out to it
  out+="$(repeat_str " " $((col - vis)))"$'\e[0m'"${g}"$'\e[0m'
  SCREEN[row]=$out
}

# panel_frame top left w h rgb title key — empty title → plain top border.
# PF_TITLE_RGB (one shot) colors the title independently of the border.
panel_frame() {
  local top=$1 left=$2 w=$3 h=$4 rgb=$5 title=$6 key=$7
  local c f b tc
  c=$(fgt "$rgb"); f=$(fgt "$RGB_FAINT"); b=$C_BOLD
  tc=$c
  if [[ -n ${PF_TITLE_RGB:-} ]]; then tc=$(fgt "$PF_TITLE_RGB"); PF_TITLE_RGB=""; fi
  # a title row may never exceed w: the key hint yields first, then the title
  if [[ -n $title ]] && (( ${#title} + 8 + (${#key} > 0 ? ${#key} + 2 : 0) > w )); then key=""; fi
  if [[ -n $title ]] && (( ${#title} + 8 > w )); then title=$(trunc "$title" $(( w > 9 ? w - 8 : 1 ))); fi
  local tl=${#title} kl=${#key}
  local kpart="" kvis=0
  if [[ -n $key ]]; then kpart=" ${key} "; kvis=$((kl + 2)); fi
  if [[ -z $title && kvis > 0 ]] && (( kvis + 3 > w )); then kpart="" kvis=0; fi
  if [[ -n $title ]]; then
    local dashes=$(( w - 4 - tl - 2 - kvis - 2 ))
    (( dashes < 0 )) && dashes=0
    scr_put "$top" "$left" "$w" \
      "${c}┌─┤ ${RS}${tc}${b}${title}${RS}${c} ├$(repeat_str "─" "$dashes")${RS}${f}${kpart}${RS}${c}─┐${RS}"
  else
    local dashes=$(( w - 3 - kvis ))
    (( dashes < 0 )) && dashes=0
    scr_put "$top" "$left" "$w" \
      "${c}┌$(repeat_str "─" "$dashes")${RS}${f}${kpart}${RS}${c}─┐${RS}"
  fi
  local r
  for ((r=top+1; r<top+h-1; r++)); do
    scr_put "$r" "$left" 1 "${c}│${RS}"
    scr_put "$r" $((left + w - 1)) 1 "${c}│${RS}"
  done
  scr_put $((top + h - 1)) "$left" "$w" "${c}└$(repeat_str "─" $((w - 2)))┘${RS}"
}

# ── meters: 18 gradient cells, red→amber→green along the SCALE (§9.3) ───────
declare -A DGRAD_CACHE DMETER_CACHE DSPARK_CACHE
dgrad_colors() { # cells → space-joined "r;g;b" per cell
  if [[ -z ${DGRAD_CACHE[$1]:-} ]]; then
    DGRAD_CACHE[$1]=$(awk -v n="$1" 'BEGIN{
      split("248 81 73",A," "); split("210 153 34",B," "); split("63 185 80",C," ")
      for(i=0;i<n;i++){ t=(i+0.5)/n
        if(t<0.5){u=t*2; r=A[1]+(B[1]-A[1])*u; g=A[2]+(B[2]-A[2])*u; b=A[3]+(B[3]-A[3])*u}
        else{u=(t-0.5)*2; r=B[1]+(C[1]-B[1])*u; g=B[2]+(C[2]-B[2])*u; b=B[3]+(C[3]-B[3])*u}
        printf "%d;%d;%d ", r, g, b } }')
  fi
  printf '%s' "${DGRAD_CACHE[$1]}"
}
dmeter() { # value cells frozen → DM (visible width = cells)
  local v=$1 n=$2 fro=${3:-0}
  local ck="$v|$n|$fro"
  if [[ -n ${DMETER_CACHE[$ck]:-} ]]; then DM=${DMETER_CACHE[$ck]}; return; fi
  local -a cols=($(dgrad_colors "$n"))
  local i out=""
  # ▆ (lower ¾ block): the top quarter of each cell stays background —
  # built-in breathing room above every meter
  for ((i=0; i<n; i++)); do
    if (( v * n > i * 100 )); then
      # hibernation freezes bars ice-blue (ux-spec §9 state treatments)
      if (( fro )); then out+="$(fgt "$RGB_ICE")▆"
      else out+="$(fgt "${cols[i]}")▆"; fi
    else out+="$(fgt "$RGB_TRACK")▆"; fi
  done
  DM="${out}${RS}"
  DMETER_CACHE[$ck]=$DM
}
dval() { # value [frozen] → threshold-colored value; frozen = ice ❄ + value
  local v=$1 fro=${2:-0}
  if (( fro )); then printf '%s' "$(fgt "$RGB_ICE")${G_FROZEN}$(printf '%3s' "$v")${RS}"; return; fi
  local rgb=$RGB_GREEN
  (( v < 50 )) && rgb=$RGB_YELLOW
  (( v < 20 )) && rgb=$RGB_RED
  printf '%s' "$(fgt "$rgb")${C_BOLD}$(printf '%3s' "$v")${RS}"
}
SPARK_CH="▁▂▃▄▅▆▇█"
dspark() { # "v1 v2 …" → DSP colored sparkline (single quiet blue, §9.3)
  # bars scale to the series' own range, like the expanded detail's history —
  # a 3-point drift reads as a slope, not identical columns; a truly flat
  # series sits mid-height. The meter next door owns the absolute level.
  local key=$1
  if [[ -n ${DSPARK_CACHE[$key]:-} ]]; then DSP=${DSPARK_CACHE[$key]}; return; fi
  local -a vs=($key)
  local lo=101 hi=-1 x
  for x in "${vs[@]}"; do
    (( x < lo )) && lo=$x
    (( x > hi )) && hi=$x
  done
  local span=$(( hi - lo )) out="" i
  for x in "${vs[@]}"; do
    if (( span == 0 )); then i=3
    else i=$(( (x - lo) * 7 / span )); fi
    out+=${SPARK_CH:i:1}
  done
  DSP="$(fgt "$RGB_BLUE")${C_DIM}${out}${RS}"
  DSPARK_CACHE[$key]=$DSP
}

# ── activity graph (cached per derive: rebuilt when data/width changes) ─────
declare -a DGRAPH_LINES
DGRAPH_KEY=""
EIGHTHS=" ▁▂▃▄▅▆▇█"
build_graph() { # evdays_str peak base_pd_x100 ndays rows gap_idx gap_days merge_idx merge_num
  local key="$1|$4|$5|${6:-}|${8:-}"
  [[ $DGRAPH_KEY == "$key" ]] && return
  DGRAPH_KEY=$key
  local -a days=($1)
  local peak=$2 base=$3 nd=$4 rows=$5
  local gap_idx=${6:-} gap_days=${7:-} merge_idx=${8:--1} merge_num=${9:-}
  (( peak < 1 )) && peak=1
  local total=${#days[@]}   # annotation indices are into the unsliced array
  days=("${days[@]:$((total - nd))}")
  local baserow=$(( rows - 1 - (base * rows) / (peak * 100) ))
  (( baserow < 0 )) && baserow=0
  (( baserow >= rows )) && baserow=$((rows - 1))

  # annotations float over the graph like the mockup: ▲ merge on the top row,
  # rest gap (ice — celebrated, not shamed) low across its own quiet region
  local merge_url=${10:-}
  local -A ANN ANNC ANNU
  if (( merge_idx >= 0 )) && [[ -n $merge_num ]]; then
    local ma="▲ #${merge_num} merged" mi=$(( merge_idx - (total - nd) )) j
    local mx=$(( mi * 2 - ${#ma} + 2 )); (( mx < 0 )) && mx=0
    (( mx + ${#ma} > nd * 2 )) && mx=$(( nd * 2 - ${#ma} ))
    if (( mi >= 0 )); then
      for ((j=0; j<${#ma}; j++)); do
        ANN[0,$((mx+j))]=${ma:j:1}; ANNC[0,$((mx+j))]=$RGB_ORANGE
        [[ -n $merge_url ]] && ANNU[0,$((mx+j))]=$merge_url
      done
    fi
  fi
  if [[ -n $gap_idx ]]; then
    local ga="└ rest gap · ${gap_days}d ┘" gi=$(( gap_idx - (total - nd) )) j
    local gx2=$(( gi * 2 - ${#ga} / 2 )); (( gx2 < 0 )) && gx2=0
    (( gx2 + ${#ga} > nd * 2 )) && gx2=$(( nd * 2 - ${#ga} ))
    local grow=$(( rows - 2 )); (( grow < 1 )) && grow=1
    if (( gi >= 0 && gx2 >= 0 )); then
      for ((j=0; j<${#ga}; j++)); do ANN[$grow,$((gx2+j))]=${ga:j:1}; ANNC[$grow,$((gx2+j))]=$RGB_ICE; done
    fi
  fi

  DGRAPH_LINES=()
  local r d v x
  for ((r=0; r<rows; r++)); do
    local line=""
    x=0
    for d in "${days[@]}"; do
      v=$d
      local hgt=$(( (v * rows * 8) / peak )) base8=$(( (rows - 1 - r) * 8 ))
      local fill=$(( hgt - base8 ))
      (( fill < 0 )) && fill=0; (( fill > 8 )) && fill=8
      local ch=${EIGHTHS:fill:1} rgb=$ACT_G0
      if (( v > 0 )); then
        local t=$(( v * 100 / peak ))
        if (( t < 31 )); then rgb=$ACT_G1
        elif (( t < 56 )); then rgb=$ACT_G2
        elif (( t < 81 )); then rgb=$ACT_G3
        else rgb=$ACT_G4; fi
      fi
      local cx
      for cx in $x $((x+1)); do
        if [[ -n ${ANN[$r,$cx]:-} ]]; then
          if [[ -n ${ANNU[$r,$cx]:-} ]]; then
            line+="$(osc8 "${ANNU[$r,$cx]}" "$(fgt "${ANNC[$r,$cx]}")${ANN[$r,$cx]}")"
          else
            line+="$(fgt "${ANNC[$r,$cx]}")${ANN[$r,$cx]}"
          fi
        elif [[ $ch == " " ]]; then
          if (( r == baserow )); then line+="$(fgt "$RGB_ORANGE")${C_DIM}╌${RS}"
          else line+=" "; fi
        else
          line+="$(fgt "$rgb")${ch}"
        fi
      done
      x=$((x+2))
    done
    DGRAPH_LINES+=("${line}${RS}")
  done
  DGRAPH_BASEROW=$baserow
}

# medal → signature color (echoes GitHub's achievement artwork)
medal_rgb() {
  case $1 in
    PS)   printf '88;166;255' ;;   # Pull Shark — shark blue
    YOLO) printf '188;140;242' ;;  # YOLO — purple
    QD)   printf '210;153;34' ;;   # Quickdraw — gold
    GB)   printf '57;197;207' ;;   # Galaxy Brain — cyan
    PE)   printf '63;185;80' ;;    # Pair Extraordinaire — green
    SS)   printf '247;120;186' ;;  # Starstruck — pink
    SP)   printf '240;136;62' ;;   # Public Sponsor — orange
    ACV)  printf '121;192;242' ;;  # Arctic Code Vault — ice
    M20)  printf '226;107;76' ;;   # Mars 2020 — mars red
    OS)   printf '163;113;247' ;;  # Open Sourcerer — violet
    HS)   printf '248;81;73' ;;    # Heart On Your Sleeve — red
    *)    # unknown medals cycle a pleasant palette by first letter
      case $(( $(printf '%d' "'${1:0:1}") % 4 )) in
        0) printf '88;166;255' ;; 1) printf '63;185;80' ;;
        2) printf '240;136;62' ;; *) printf '188;140;242' ;;
      esac ;;
  esac
}
MEDAL_INK="13;17;23"   # dark text on the solid chip (GitHub-dark surface)
medal_chip() { # code label → CHIP (colored, solid fill) ; plain width = ${#label}+2
  local rgb; rgb=$(medal_rgb "$1")
  CHIP=$'\e[48;2;'"$rgb"$'m\e[38;2;'"$MEDAL_INK"$'m\e[1m '"$2"$' \e[0m'
}

# feed tag → the terminal's honest badge: [tag] in its identity color
feed_tag_chip() { # tag → FCHIP (colored; plain width = ${#tag} + 2)
  local rgb; rgb=$(feed_tag_rgb "$1")
  FCHIP="$(fgt "$rgb")[$1]${RS}"
}

# feed tag → color
feed_tag_rgb() {
  case $1 in
    merge) printf '%s' "$RGB_GREEN" ;;
    review) printf '%s' "$RGB_CYAN" ;;
    mention) printf '%s' "$RGB_YELLOW" ;;
    medal) printf '%s' "$RGB_ORANGE" ;;
    rest) printf '%s' "$RGB_ICE" ;;
    sec) printf '%s' "$RGB_RED" ;;
    *) printf '%s' "$RGB_MUTED" ;;
  esac
}

# a real pixel-art poop: 8×6 palette grid rendered with the same half-block
# technique as the pets — swirl, highlight glint, shaded base (built once)
declare -a POOPS=()
poop_sprite() {
  (( ${#POOPS[@]} )) && return
  local -a g=("...MM..." "..MMM..." ".MMMMM.." ".MMHMMM." "MMMMMMMM" "DDDDDDDD")
  local -A pc=([M]="146;100;60" [D]="104;68;38" [H]="181;134;90")
  local y x t b tc bc line
  for ((y=0; y<6; y+=2)); do
    line=""
    for ((x=0; x<8; x++)); do
      t=${g[y]:x:1}; b=${g[y+1]:x:1}
      tc=""; bc=""
      [[ $t != "." ]] && tc=${pc[$t]}
      [[ $b != "." ]] && bc=${pc[$b]}
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
    POOPS+=("$line")
  done
}

# ── shared footer: btop key buttons left, sync cell right ───────────────────
dsync_cell() { # → DSY_P (plain) DSY_C (colored)
  local st now2 age2 MU FA
  MU=$(fgt "$RGB_MUTED"); FA=$(fgt "$RGB_FAINT")
  st=$(net_status); now2=$(date +%s); age2=$(age_str $((now2 - $(net_last_ok))))
  if [[ -n ${FIXDIR:-} ]]; then
    DSY_P="fixtures"; DSY_C="${FA}fixtures${RS}"
  elif [[ -n ${FETCH_PID:-} ]] && kill -0 "$FETCH_PID" 2>/dev/null; then
    DSY_P="${G_SPIN} syncing…"; DSY_C="$(fgt "$RGB_YELLOW")${G_SPIN}${RS}${MU} syncing…${RS}"
  else
    case $st in
      ok) DSY_P="${G_DOT_OK} synced ${age2} ago"
          DSY_C="$(fgt "$RGB_GREEN")${G_DOT_OK} synced${RS}${MU} ${age2} ago${RS}" ;;
      retry) DSY_P="${G_WAIT} retrying in $(net_retry_in)s"
             DSY_C="$(fgt "$RGB_YELLOW")${DSY_P}${RS}" ;;
      *) DSY_P="offline · data ${age2} old"; DSY_C="${FA}${DSY_P}${RS}" ;;
    esac
  fi
}
dense_footer() { # row "key label"… — right side is the sync cell unless
  local ftr=$1; shift          # DFOOT_RIGHT is set (consumed, one shot)
  local kx=1 kk MU FA
  MU=$(fgt "$RGB_MUTED"); FA=$(fgt "$RGB_FAINT")
  for kk in "$@"; do
    local kl2=${kk%% *} kw=${kk#* }
    scr_put "$ftr" "$kx" $(( ${#kl2} + ${#kw} + 3 )) "${FA}[${RS}$(fgt "$RGB_RED")${C_BOLD}${kl2}${RS}${FA}]${RS}${MU} ${kw}${RS}"
    kx=$(( kx + ${#kl2} + ${#kw} + 4 ))
  done
  local DSY_P DSY_C
  if [[ -n ${DFOOT_RIGHT_C:-} ]]; then
    DSY_P=${DFOOT_RIGHT_P:-}; DSY_C=$DFOOT_RIGHT_C
    DFOOT_RIGHT_C="" DFOOT_RIGHT_P=""
  elif [[ -n ${DFOOT_RIGHT:-} ]]; then
    DSY_P=$DFOOT_RIGHT; DSY_C="${FA}${DFOOT_RIGHT}${RS}"; DFOOT_RIGHT=""
  else
    dsync_cell
  fi
  scr_put "$ftr" $((COLS - ${#DSY_P} - 2)) ${#DSY_P} "$DSY_C"
}

# ── the dense main screen ───────────────────────────────────────────────────
draw_dense() { # assoc_name self(1) — friends get the same panels from their
  local -n P=$1  # public data: no ✉/⎘ (theirs is private), no friends table,
  local self=${2:-1}   # their feed full-width (§5.6 re-skinned for dense)
  scr_reset
  scene_calc   # day/night + season from the wall clock (before any palette)
  local MU FA IN
  MU=$(fgt "$RGB_MUTED"); FA=$(fgt "$RGB_FAINT"); IN=$(fgt "$RGB_INK")
  local petrgb; petrgb=$(hex_to_rgb "${P[COLOR_HEX]:-#dea584}")
  local PC1; PC1=$(fgt "$petrgb")

  # state treatments (ux-spec §9): sick shifts EVERY panel border to red —
  # at btop density the border color is the fastest thing the eye catches
  local frozen; frozen=$(frozen_disp "$1")
  local BR_PET=$petrgb BR_VIT=$RGB_GREEN BR_ACT=$RGB_ACT BR_FR=$RGB_BLUE BR_FEED=$RGB_PURPLE
  if [[ $ANIM_STATE == sick ]]; then
    BR_PET=$RGB_RED BR_VIT=$RGB_RED BR_ACT=$RGB_RED BR_FR=$RGB_RED BR_FEED=$RGB_RED
  fi

  local pw=$(( COLS * 54 / 100 ))
  local rw=$(( COLS - pw ))
  # distribute rows: pet/vitals first, then activity, then friends/feed —
  # every panel shrinks before any panel disappears
  local avail=$(( LINES - 2 ))
  local act_h=7 ff_h=4
  local pv_h=$(( avail - act_h - ff_h ))
  if (( pv_h > 17 )); then      # 17: two rows of sky above a 9-row pet
    local extra=$(( pv_h - 17 )); pv_h=17
    local a=$(( extra < 4 ? extra : 4 )); act_h=$((act_h + a)); extra=$((extra - a))
    ff_h=$(( ff_h + extra ))
  elif (( pv_h < 11 )); then
    pv_h=11
    ff_h=$(( avail - act_h - pv_h )); (( ff_h < 3 )) && ff_h=3
    act_h=$(( avail - pv_h - ff_h ))
    if (( act_h < 5 )); then act_h=5; pv_h=$(( avail - act_h - ff_h )); fi
    (( pv_h < 8 )) && pv_h=8
  fi
  local pv_top=1 act_top=$((1 + pv_h)) ff_top=$((1 + pv_h + act_h)) ftr=$((LINES - 1))

  # ── header ── (the live right cells own the corner; the identity on the
  # left sheds its id, then its language, rather than evicting them)
  local vshort=${VERSION%.*}
  local hlang; hlang=$(tr '[:upper:]' '[:lower:]' <<<"${P[TOP_LANG]:-?}")
  local clock; printf -v clock '%(%H:%M:%S)T' -1
  # the cell shows "–" unless the cached value is a sane 0..5000 integer —
  # a corrupted remaining must never render as "api -43929394/5000"
  local rem used="–"; rem=$(api_remaining)
  [[ $rem =~ ^[0-9]+$ ]] && (( rem <= 5000 )) && used=$((5000 - rem))
  local hr_p="" hr_c=""
  local show=1
  (( TICK < BADGE_BLINK_UNTIL )) && (( (TICK / 2) % 2 )) && show=0
  if [[ $self == 1 && $AUTH_MODE != none ]] && (( show )); then
    if (( ${P[MAIL]:-0} > 0 )); then
      # the mail badge pulses gently (mockup @keyframes pulse, 2.4s)
      local pulse=""
      (( (TICK / 5) % 2 )) && pulse=$C_DIM
      hr_p+="[${G_MAIL} ${P[MAIL]}] "
      hr_c+="$(fgt "$RGB_ORANGE")${pulse}$(osc8 "https://github.com/notifications" "[${G_MAIL} ${P[MAIL]}]")${RS} "
    else
      # inbox-zero still keeps its badge — quiet, faint, clickable
      hr_p+="[${G_MAIL} 0] "
      hr_c+="${FA}$(osc8 "https://github.com/notifications" "[${G_MAIL} 0]")${RS} "
    fi
    if (( ${P[REVIEW_REQ]:-0} > 0 )); then
      hr_p+="[${G_SCROLL} ${P[REVIEW_REQ]}] "
      hr_c+="$(fgt "$RGB_CYAN")$(osc8 "${P[REVIEW_URL]}" "[${G_SCROLL} ${P[REVIEW_REQ]}]")${RS} "
    fi
  fi
  hr_p+="· api $used/5000 · $clock"
  hr_c+="${FA}· ${RS}${MU}api ${RS}$(fgt "$RGB_GREEN")${C_BOLD}$used${RS}${MU}/5000 · ${RS}${IN}${C_BOLD}$clock${RS}"
  scr_put 0 $((COLS - ${#hr_p} - 1)) ${#hr_p} "$hr_c"

  local avail_left=$(( COLS - ${#hr_p} - 3 ))
  local hl_p="gitagotchi v$vshort  @${P[LOGIN]} · id ${P[ID]} · ${hlang}"
  local hl_c="${PC1}${C_BOLD}gitagotchi${RS} ${FA}v$vshort${RS}  $(osc8 "https://github.com/${P[LOGIN]}" "${IN}${C_BOLD}@${P[LOGIN]}${RS}")${MU} · id ${P[ID]} · ${hlang}${RS}"
  if (( ${#hl_p} > avail_left )); then
    hl_p="gitagotchi v$vshort  @${P[LOGIN]} · ${hlang}"
    hl_c="${PC1}${C_BOLD}gitagotchi${RS} ${FA}v$vshort${RS}  $(osc8 "https://github.com/${P[LOGIN]}" "${IN}${C_BOLD}@${P[LOGIN]}${RS}")${MU} · ${hlang}${RS}"
  fi
  if (( ${#hl_p} > avail_left )); then
    hl_p="gitagotchi v$vshort  @${P[LOGIN]}"
    hl_c="${PC1}${C_BOLD}gitagotchi${RS} ${FA}v$vshort${RS}  $(osc8 "https://github.com/${P[LOGIN]}" "${IN}${C_BOLD}@${P[LOGIN]}${RS}")"
  fi
  scr_put 0 1 ${#hl_p} "$hl_c"
  # event flash (merge / wake) rides the header, like the cozy title bar
  if (( TICK < FLASH_UNTIL )) && [[ -n $FLASH_TEXT ]] \
     && (( ${#hl_p} + 3 + ${#FLASH_TEXT} + 2 <= COLS - ${#hr_p} - 2 )); then
    scr_put 0 $(( ${#hl_p} + 3 )) $(( ${#FLASH_TEXT} + 2 )) \
      "$(osc8 "$FLASH_URL" "$(fgt "$RGB_GREEN")${C_BOLD}▸ ${FLASH_TEXT}${RS}")"
  fi

  # ── pet panel ──
  local pt_title; pt_title=$(tr '[:upper:]' '[:lower:]' <<<"${P[NAME]}")
  [[ ${P[STAGE]:-} == egg ]] && pt_title="egg"   # the name hatches with the pet
  panel_frame $pv_top 0 "$pw" "$pv_h" "$BR_PET" "$pt_title" "home"
  local piw=$((pw - 4)) pix0=2
  local ground=$(( pv_top + pv_h - 5 ))
  local stage_top=$(( pv_top + 1 )) stage_h=$(( ground - stage_top ))

  # medal shelf: solid color chips top-right — each medal wears its own color.
  # shelf_lim reserves the shelf's columns so the pet never paints over it.
  local shelf_lim=$(( pw - 2 ))
  if [[ ${P[MEDALS_OK]:-0} == 1 && -n ${P[MEDALS_RAW]:-} ]]; then
    local -a codes=() labels=()
    local m IFS=';'
    for m in ${P[MEDALS_RAW]}; do
      local mc lb; mc=$(medal_code "${m%%|*}"); lb=$mc
      (( ${m##*|} > 1 )) && lb+=" ×${m##*|}"
      codes+=("$mc"); labels+=("$lb")
    done
    unset IFS
    local lbl="medals"
    scr_put "$stage_top" $((pw - 2 - ${#lbl})) ${#lbl} "${FA}${lbl}${RS}"
    # pack two chips per row; plain width per chip = label + 2 (solid padding)
    local r1p="" r1c="" r2p="" r2c="" over="" i CHIP
    for i in "${!codes[@]}"; do
      medal_chip "${codes[i]}" "${labels[i]}"
      if (( i < 2 )); then
        r1p+="${r1p:+ } ${labels[i]} "; r1c+="${r1c:+ }$CHIP"
      elif (( i < 4 )); then
        r2p+="${r2p:+ } ${labels[i]} "; r2c+="${r2c:+ }$CHIP"
      else over="+$(( ${#codes[@]} - 4 ))"; break; fi
    done
    if [[ -n $over ]]; then r2p+=" $over"; r2c+=" ${FA}${over}${RS}"; fi
    local wmax=${#r1p}; (( ${#r2p} > wmax )) && wmax=${#r2p}
    shelf_lim=$(( pw - 3 - wmax ))
    local aurl="https://github.com/${P[LOGIN]}?tab=achievements"
    [[ -n $r1p ]] && scr_put $((stage_top + 1)) $((pw - 2 - ${#r1p})) ${#r1p} "$(osc8 "$aurl" "$r1c")"
    [[ -n $r2p ]] && scr_put $((stage_top + 2)) $((pw - 2 - ${#r2p})) ${#r2p} "$(osc8 "$aurl" "$r2c")"
  elif [[ ${P[MEDALS_OK]:-0} != 1 ]]; then
    scr_put "$stage_top" $((pw - 22)) 19 "${FA}medals: unavailable${RS}"
  fi

  # cobwebs: 90+ days quiet — corner web + spider on a swaying thread
  if cobwebbed "$1"; then
    local -a web=("${COBWEB_TL[@]}")
    local wi
    for wi in "${!web[@]}"; do
      scr_put $((stage_top + wi)) 2 "${#web[wi]}" "${FA}${C_DIM}${web[wi]}${RS}"
    done
    local spx=$(( pix0 + piw / 3 + (TICK / 8) % 2 ))
    local spl=$(( 2 + (TICK / 16) % 2 ))
    local sr
    for ((sr=0; sr<spl && stage_top + sr < ground - 1; sr++)); do
      scr_put $((stage_top + sr)) "$spx" 1 "${FA}${C_DIM}╎${RS}"
    done
    (( stage_top + spl < ground )) && scr_put $((stage_top + spl)) "$spx" 1 "${MU}●${RS}"
  fi

  # the pet (pixel; ANIM_* prepared by the caller's state machine) — while
  # hatching OR still in the egg stage, the egg holds the stage: nobody sees
  # the pet before hatch day (§5.9)
  if { [[ $ANIM_STATE == hatch ]] && (( ${HATCH_PHASE:-3} < 3 )); } || [[ ${P[STAGE]:-} == egg ]]; then
    local ex etop eh ei
    if [[ -n $PIX_MODE && -n ${PIXF[egg/idle_1]:-} ]]; then
      # the pixel egg — same half-block style as the pet, cracks and all
      local eframe=idle_1 exoff=${HATCH_TILT:-0}
      if [[ $ANIM_STATE == hatch ]] && (( HATCH_PHASE == 2 )); then
        eframe=crack_$(( (TICK / 2) % 2 + 1 ))
        exoff=$(( (TICK % 2) * 2 - 1 ))          # shaking as it splits
      elif [[ $ANIM_STATE != hatch ]]; then
        # egg stage: the egg wiggles — more as warmth grows (§5.9)
        local wob=12; (( ${P[WARMTH]:-0} > 50 )) && wob=6
        exoff=0
        (( (TICK / wob) % 4 == 1 )) && exoff=-1
        (( (TICK / wob) % 4 == 3 )) && exoff=1
      fi
      pix_palette egg "${P[COLOR_HEX]:-#dea584}" 0
      pix_render egg "$eframe" 0 0 0
      eh=$PIXOUT_H
      ex=$(( pix0 + (piw - PIXOUT_W) / 2 + exoff ))
      (( ex < pix0 )) && ex=$pix0
      etop=$(( ground - eh ))
      # a short stage clips the egg's bottom, never the crack up top
      (( etop < stage_top )) && etop=$stage_top
      for ((ei=0; ei<eh; ei++)); do
        (( etop + ei >= ground )) && break
        scr_put $((etop + ei)) "$ex" "$PIXOUT_W" "${PIXOUT[ei]}"
      done
      GLEE_TX=$(( ex + PIXOUT_W / 2 )); GLEE_TY=$(( ground - 2 ))
      GLEE_HX=$GLEE_TX GLEE_HY=$etop
    else
      egg_frame "${HATCH_TILT:-0}" "$(fg "${P[COLOR256]:-180}")"
      eh=${#SPCOMP_PLAIN[@]}
      ex=$(( pix0 + (piw - 7) / 2 + PET_XOFF ))
      (( ex < pix0 )) && ex=$pix0
      etop=$(( ground - eh ))
      for ei in "${!SPCOMP_PLAIN[@]}"; do
        (( etop + ei < stage_top || etop + ei >= ground )) && continue
        scr_put $((etop + ei)) "$ex" "${#SPCOMP_PLAIN[ei]}" "${SPCOMP_COL[ei]}"
      done
      GLEE_TX=$(( ex + 3 )); GLEE_TY=$(( ground - 2 ))
      GLEE_HX=$GLEE_TX GLEE_HY=$etop
    fi
    # floaters (sparks) still rise around the egg
    local fl
    for fl in "${FLOATERS[@]}"; do
      local frow=${fl%%|*} rest=${fl#*|}
      local fcol=${rest%%|*} rest2=${rest#*|}
      local fch=${rest2%%|*} fcolor=${rest2#*|}
      (( stage_top + frow >= ground )) && continue
      scr_put $((stage_top + frow)) $((pix0 + fcol)) "${#fch}" "${fcolor}${fch}${RS}"
    done
  else
  local faint=0
  [[ $ANIM_STATE == sick ]] && faint=1
  pet_compose "$1" "$ANIM_FRAME" "$ANIM_BLINK" "$faint"
  # company's over: everyone shrinks to half scale so the party always fits
  if [[ $self == 1 && -n ${P[VISITORS]:-} ]] && \
     pix_render_half "${P[SPECIES]}" "${P[COLOR_HEX]:-#dea584}" "$ANIM_FRAME"; then
    PET_LINES=("${PIXH[@]}"); PET_W=12; PET_H=${#PIXH[@]}
  fi
  local petx=$(( pix0 + (piw - PET_W) / 2 + PET_XOFF ))
  # ...and stands still at the left edge to host (no wandering with guests)
  [[ $self == 1 && -n ${P[VISITORS]:-} ]] && petx=$(( pix0 + 1 ))
  # the shelf only blocks pets tall enough to reach its rows — short pets
  # run the full stage (the fetch chase needs the room)
  local pxmax=$(( pw - 3 - PET_W ))
  (( ground - PET_H < stage_top + 3 )) && pxmax=$(( shelf_lim - PET_W ))
  (( petx > pxmax )) && petx=$pxmax
  # the reading corner is furniture (curiosity ≥ 75): the pet strolls up to
  # the pile and STOPS — never onto it, so the corner can't blink in and out
  # as the pet wanders. If pet + pile can't share the stage, the pile yields.
  local bkw=0
  if [[ $VIG_CUR == books && $ANIM_STATE == idle && -n $PIX_MODE && \
        -n ${PIXF[books/idle_1]:-} && -z ${P[VISITORS]:-} ]]; then
    bkw=8; (( piw >= 59 )) && bkw=12
    if (( pix0 + 2 + bkw <= pxmax )); then
      (( petx < pix0 + 2 + bkw )) && petx=$(( pix0 + 2 + bkw ))
    else
      bkw=0
    fi
  fi
  (( petx < pix0 )) && petx=$pix0
  # exported for anim_update: how far right the runner may actually go
  PET_XMAX=$(( pxmax - pix0 - (piw - PET_W) / 2 ))
  # feet stay on the ground; in a short panel the top of the sprite clips
  local pet_top=$(( ground - PET_H )) i skip=0
  GLEE_TX=$(( petx + PET_W / 2 ))          # the glee flies to the pet's mouth
  GLEE_TY=$(( pet_top + PET_H / 2 ))
  GLEE_HX=$GLEE_TX GLEE_HY=$(( pet_top + 1 ))   # …and the halo rings the head
  if (( pet_top < stage_top )); then skip=$(( stage_top - pet_top )); pet_top=$stage_top; fi
  for ((i=skip; i<PET_H; i++)); do
    local prr=$(( pet_top + i - skip ))
    (( prr >= ground )) && break
    scr_put "$prr" "$petx" "$PET_W" "${PET_LINES[i]}"
  done
  # toy ball (curiosity ≥ 60) and flies (§5.3 vignettes carry over)
  if [[ $VIG_CUR == ball && $ANIM_STATE == idle ]]; then
    local bx=$(( petx - 5 - ((TICK / 6) % 2) * 2 ))
    scr_put $((ground - 1)) "$bx" 1 "$(fgt "$RGB_BLUE")${G_BALL}${RS}"
  fi
  # the book pile (curiosity ≥ 75): a fixed reading corner at the stage's
  # left wall, five books of different colors and sizes. bkw was settled
  # above, where the pet's stroll was clamped clear of the corner — so
  # when bkw > 0 the pile ALWAYS draws (no blink)
  if [[ $VIG_CUR == books && $ANIM_STATE == idle ]]; then
    if (( bkw > 0 )); then
      pix_palette books "${PIXREF[books]}" 0
      local bframe=idle_1
      (( bkw == 8 )) && bframe=narrow
      pix_render books "$bframe" 0
      local bkx=$(( pix0 + 1 )) bi
      for ((bi=0; bi<PIXOUT_H; bi++)); do
        scr_put $(( ground - PIXOUT_H + bi )) "$bkx" "$PIXOUT_W" "${PIXOUT[bi]}"
      done
    elif [[ -z $PIX_MODE ]]; then
      # glyph-tier stand-in: a tiny spine pile in the same corner
      local bg2="≣"; [[ $TIER == A ]] && bg2="="
      (( petx > pix0 + 3 )) && scr_put $((ground - 1)) $((pix0 + 1)) 2 "$(fgt "$RGB_YELLOW")${bg2}${bg2}${RS}"
    fi
  fi
  # review duty note: the spear is HELD now — pix_render blits it into the
  # pet's own grid (OUTBOUND7 ≥ 3, via pet_compose), so it wanders, wags
  # and flips with the pet instead of standing loose on the stage
  if [[ $VIG_CUR == flies ]]; then
    local fly=$G_FLY1; (( TICK % 4 < 2 )) && fly=$G_FLY2
    scr_put "$pet_top" $((petx - 4)) 3 "${FA}${fly}${RS}"
  fi
  # floaters (hearts, zZz, +N) — panel-relative rows from anim_update
  local fl
  for fl in "${FLOATERS[@]}"; do
    local frow=${fl%%|*} rest=${fl#*|}
    local fcol=${rest%%|*} rest2=${rest#*|}
    local fch=${rest2%%|*} fcolor=${rest2#*|}
    local frr=$(( stage_top + frow )) ffx=$(( pix0 + fcol ))
    (( frr >= ground )) && continue
    # the sprite owns its cells — a floater inside slides beside the head
    if (( frr >= pet_top && ffx + ${#fch} > petx && ffx < petx + PET_W )); then
      ffx=$(( petx + PET_W + 1 ))
    fi
    scr_put "$frr" "$ffx" "${#fch}" "${fcolor}${fch}${RS}"
  done

  # visitors (last-hour interactions): their pets drop by IN PERSON —
  # full pixel sprites on the ground beside the host, each animated in its
  # own linguist color; when a sprite doesn't fit, the mini face stands in
  if [[ $self == 1 && -n ${P[VISITORS]:-} ]]; then
    local -a vlog=(${P[VISITORS]})
    # (re)load visitor pets when the guest list or their caches change
    local vkey="${P[VISITORS]}" vl2
    for vl2 in "${vlog[@]}"; do
      [[ -f $CACHE_ROOT/$vl2/state.env ]] && vkey+="+$vl2"
    done
    if [[ ${VPET_KEY:-} != "$vkey" ]]; then
      VPET_KEY=$vkey
      VPET1=(); VPET2=(); VPET3=()
      local vi3=1
      for vl2 in "${vlog[@]}"; do
        (( vi3 > 3 )) && break
        [[ -f $CACHE_ROOT/$vl2/state.env ]] && load_state "VPET$vi3" "$vl2"
        vi3=$((vi3 + 1))
      done
    fi
    local mainw=$PET_W mainh=$PET_H
    # gaps compress before anyone is turned away (sprites carry their own
    # transparent margins, so touching still reads as spaced)
    local vgap=2 vn=${#vlog[@]}
    (( vn > 3 )) && vn=3
    while (( vgap > 0 && petx + PET_W + vn * (12 + vgap) > pw - 2 )); do
      vgap=$(( vgap - 1 ))
    done
    local vrcur=$(( petx + PET_W + vgap ))
    (( vrcur <= petx + PET_W )) && vrcur=$(( petx + PET_W + 1 ))
    local vlcur=$(( petx - 2 ))
    local vi2
    for vi2 in "${!vlog[@]}"; do
      (( vi2 >= 3 )) && break
      local vlogin=${vlog[vi2]}
      local vslot="VPET$((vi2 + 1))"
      unset -n VPQ 2>/dev/null; local -n VPQ=$vslot
      local drew=0
      if [[ -n ${VPQ[SPECIES]:-} ]]; then
        local vframe="idle_$(( (TICK / 3 + vi2) % 2 + 1 ))"
        [[ ${VPQ[HIB]:-0} == 1 ]] && vframe="hibernate_$(( (TICK / 6) % 2 + 1 ))"
        if pix_render_half "${VPQ[SPECIES]}" "${VPQ[COLOR_HEX]:-#dea584}" "$vframe"; then
          local vw=12 vh=${#PIXH[@]}
          local vpx=-1
          if (( vrcur + vw <= pw - 2 )); then
            vpx=$vrcur; vrcur=$(( vrcur + vw + vgap ))
          elif (( vlcur - vw >= pix0 )); then
            vlcur=$(( vlcur - vw )); vpx=$vlcur; vlcur=$(( vlcur - 2 ))
          fi
          if (( vpx >= 0 )); then
            local vtop=$(( ground - vh )) vk
            (( vtop < stage_top )) && vtop=$stage_top
            for ((vk=0; vk<vh; vk++)); do
              (( vtop + vk >= ground )) && break
              scr_put $(( vtop + vk )) "$vpx" "$vw" "${PIXH[vk]}"
            done
            drew=1
          fi
        fi
      fi
      if (( ! drew )); then
        # mini fallback: face + name, or just the face when tight
        local vrowd=${FRROW[$vlogin]:-}
        local vtxt vcolc
        if [[ -n $vrowd ]]; then
          local vname=${vrowd%%|*} vr2=${vrowd#*|}
          local vmini=${vr2%%|*} vr3=${vr2#*|}
          local vc256=${vr3%%|*}
          vtxt="${vmini} ${vname}"
          vcolc=$(fg "$vc256")
        else
          vtxt="(o) @${vlogin}"   # fills in once the background fetch lands
          vcolc=$MU
        fi
        local vform
        for vform in "$vtxt" "${vtxt%% *}"; do
          if (( vrcur + ${#vform} <= pw - 2 )); then
            scr_put $((ground - 1)) "$vrcur" ${#vform} "${vcolc}${vform}${RS}"
            vrcur=$(( vrcur + ${#vform} + 2 ))
            break
          elif (( vlcur - ${#vform} >= pix0 )); then
            vlcur=$(( vlcur - ${#vform} ))
            scr_put $((ground - 1)) "$vlcur" ${#vform} "${vcolc}${vform}${RS}"
            vlcur=$(( vlcur - 2 ))
            break
          fi
        done
      fi
    done
    PET_W=$mainw PET_H=$mainh
  fi
  fi

  # cleanliness made visible: a spotless stage stays spotless; as CLEAN
  # falls, mess piles up on the ground — 1 item under 85 down to 4 under 25
  # (the §5.3 flies already orbit the pet; this is what they're here for)
  local mess=0 mclean=${P[CLEAN]:-100}
  (( mclean < 85 )) && mess=$(( 1 + (84 - mclean) / 20 ))
  (( mess > 4 )) && mess=4
  if (( mess > 0 )); then
    # every pile is the 8×6 pixel sprite — no ASCII stand-ins; the count
    # (1..4) is the dirtiness meter
    local -a mfrac=(4 82 28 58)
    local mi3
    for ((mi3=0; mi3<mess; mi3++)); do
      local mx3=$(( pix0 + (piw - 8) * ${mfrac[mi3]} / 100 ))
      if [[ -n $PIX_MODE ]]; then
        poop_sprite
        local pr3
        for ((pr3=0; pr3<3; pr3++)); do
          (( ground - 3 + pr3 < stage_top )) && continue
          scr_put $(( ground - 3 + pr3 )) "$mx3" 8 "${POOPS[pr3]}"
        done
      else
        # pure-ASCII tier: the simplest mound
        scr_put $((ground - 2)) $((mx3 + 1)) 3 "$(fgt "146;100;60")▄█▄${RS}"
        scr_put $((ground - 1)) "$mx3" 5 "$(fgt "146;100;60")▀▀▀▀▀${RS}"
      fi
    done
  fi

  # ── day/night + seasons (plan.md §11, unparked): the wall clock dresses
  # the stage. Every ornament is a single 1-cell scr_put placed AFTER the
  # pet, props and medals — scr_emit's x-order rule makes a late 1-wide
  # segment yield to anything already on the row, so the sky can never eat
  # a medal chip or shove a border. A summer noon adds nothing: the default
  # frame stays mockup-canonical.
  local sch=$(( stage_h > 1 ? stage_h : 1 ))
  if (( SCENE_NIGHT )); then
    # crescent top-left (cobwebs were put first and win the corner) + a
    # starfield hashed from the column index; stars twinkle out on TICK
    scr_put "$stage_top" $((pix0 + 2)) 1 "$(fgt "216;222;235")${G_MOON}${RS}"
    # stars keep to the upper 3/5 of the stage — low ones read as fireflies
    local skyh=$(( sch * 3 / 5 )) sk sh sx sy
    (( skyh < 1 )) && skyh=1
    for ((sk=0; sk<(piw - 8) / 7; sk++)); do
      sh=$(( (sk * 20 + 56) % 97 ))
      sx=$(( pix0 + 5 + sk * 7 + sh % 5 ))
      sy=$(( stage_top + sh % skyh ))
      (( sx >= pw - 3 )) && continue
      (( (${TICK:-0} / 4 + sk) % 6 == 0 )) && continue   # twinkle
      local sg=$G_HORIZ sc="150;160;185"
      # column-keyed like winter's big flake: however the pet occludes the
      # field, the survivors always mix motes and sparks
      (( sk % 3 == 1 )) && { sg=$G_SPARK; sc="205;214;235"; }
      scr_put "$sy" "$sx" 1 "$(fgt "$sc")${sg}${RS}"
    done
  fi
  case $SCENE_SEASON in
    winter)
      # snowfall: flakes sink with TICK, phase-shifted per column so they
      # never fall in a sheet; every third is the big ❄, the rest are motes
      local wk wh wx wy
      for ((wk=0; wk<(piw - 4) / 6; wk++)); do
        wh=$(( (wk * 40503 + 17) % 89 ))
        wx=$(( pix0 + 2 + wk * 6 + wh % 4 ))
        wy=$(( stage_top + (wh + ${TICK:-0} / 2 + wk) % sch ))
        (( wx >= pw - 3 )) && continue
        local wg=$G_HORIZ
        (( wk % 3 == 0 )) && wg=$G_FROZEN   # column-keyed: flake 0 sits
                                            # stage-left, clear of the pet
        scr_put "$wy" "$wx" 1 "$(fgt "170;190;215")${wg}${RS}"
      done ;;
    spring)
      # three flowers rooted at fixed fractions of the stage floor
      local -a fxf=(12 46 82) fxc=("247;120;186" "210;153;34" "232;232;242")
      local fk2 fx2
      for fk2 in 0 1 2; do
        fx2=$(( pix0 + (piw - 1) * ${fxf[fk2]} / 100 ))
        scr_put $((ground - 1)) "$fx2" 1 "$(fgt "${fxc[fk2]}")${G_FLOWER}${RS}"
      done ;;
    autumn)
      # falling leaves: sparser than snow, drifting sideways as they sink
      local lk lh lx ly lyo
      local -a lcl=("224;136;62" "192;98;48" "210;153;34")
      for ((lk=0; lk<(piw - 4) / 9; lk++)); do
        lh=$(( (lk * 48271 + 7) % 83 ))
        lyo=$(( (lh + ${TICK:-0} / 3 + lk * 2) % sch ))
        ly=$(( stage_top + lyo ))
        lx=$(( pix0 + 2 + lk * 9 + (lh + lyo) % 5 ))
        (( lx >= pw - 3 )) && continue
        scr_put "$ly" "$lx" 1 "$(fgt "${lcl[lk % 3]}")${G_LEAF}${RS}"
      done ;;
  esac

  # ground · nameplate · voice (mockup .ground/.nameplate/.voice) — the
  # ground keeps the season underfoot (frost / fresh grass / leaf litter);
  # night dims whatever the season laid down
  local gnd=$RGB_GROUND
  case $SCENE_SEASON in
    winter) gnd="96;108;128" ;;
    spring) gnd="56;84;56" ;;
    autumn) gnd="92;66;40" ;;
  esac
  (( SCENE_NIGHT )) && { moonlit "$gnd"; gnd=$MLIT; }
  scr_put "$ground" 2 $((pw - 4)) "$(fgt "$gnd")$(repeat_str "·" $((pw - 4)))${RS}"
  # nameplate: name · meta · lang chip — drop the chip, then the year, to fit
  local lang_lc; lang_lc=$(tr '[:upper:]' '[:lower:]' <<<"${P[TOP_LANG]:-?} ${P[COLOR_HEX]}")
  local np_name=${P[NAME]}
  local np_meta=" · ${P[SPECIES_LABEL]} · ${P[STAGE]} · est. ${P[CREATED_YEAR]}"
  if [[ ${P[STAGE]:-} == egg ]]; then
    # no spoilers: name and species stay secret until hatch day (§5.9)
    local np_hd=$(( 7 - ${P[ACCT_DAYS]:-0} )); (( np_hd < 1 )) && np_hd=1
    np_name="?"
    np_meta=" · egg · hatches in ${np_hd}d"
  fi
  local np_chip="  ■ ${lang_lc}"
  local np_p="${np_name}${np_meta}${np_chip}"
  if (( ${#np_p} > pw - 4 )); then np_chip=""; np_p="${np_name}${np_meta}"; fi
  if (( ${#np_p} > pw - 4 )); then np_meta=" · ${P[SPECIES_LABEL]} · ${P[STAGE]}"; np_p="${np_name}${np_meta}"; fi
  local npx=$(( (pw - ${#np_p}) / 2 )); (( npx < 2 )) && npx=2
  local lang_url="https://github.com/${P[LOGIN]}?tab=repositories&language=$(tr '[:upper:]' '[:lower:]' <<<"${P[TOP_LANG]:-}")"
  scr_put $((ground + 1)) "$npx" ${#np_p} \
    "${IN}${C_BOLD}${np_name}${RS}${MU}${np_meta}${RS}${np_chip:+$(osc8 "$lang_url" "${PC1}${np_chip}${RS}")}"
  if [[ -n $VOICE_CUR ]]; then
    local vt; vt=$(marquee "$VOICE_CUR" $((pw - 8)))
    scr_put $((ground + 3)) 3 $(( ${#vt} + 2 )) \
      "$(osc8 "${VOICE_URL:-}" "$(fgt "$RGB_VOICE")${C_ITAL}“${vt}”${RS}")"
  fi

  # ── vitals panel ── (1-col gutter between columns, like the mockup grid gap)
  panel_frame $pv_top $((pw + 1)) $((rw - 1)) "$pv_h" "$BR_VIT" "vitals" "s"
  local vx=$((pw + 3)) viw=$((rw - 5))
  # each row wears a 5-cell sparkline: the 30-point derived history bucketed
  # into five means, scaled to its own range (dspark) — shape, not level
  local lab_w=12 spark_w=5 val_w=3
  (( viw < 29 )) && spark_w=0        # narrow: history yields to the meter
  local cells=$(( viw - lab_w - spark_w - val_w - 3 ))
  (( cells > 18 )) && cells=18
  (( cells < 6 )) && cells=6
  local -a vkeys=(HAPPINESS HUNGER ENERGY MOOD FITNESS CLEAN CURIOSITY SOCIAL WISDOM HEALTH)
  local -a vnames=(happiness hunger energy mood fitness clean curiosity social wisdom health)
  local dsel=${DSEL:--1}
  local vr=$((pv_top + 1)) k
  for k in "${!vkeys[@]}"; do
    # the inspector line reserves the capnote row while it's active
    (( vr >= pv_top + pv_h - 1 - (dsel >= 0 ? 1 : 0) )) && break
    local key=${vkeys[k]} nm=${vnames[k]} v=${P[${vkeys[k]}]:-}
    local hist=${P[HIST_${key}]:-}
    # every label links to the page that raises the stat — the fix-it menu
    # semantics of the stat detail panel (§5.4), one Cmd+click away
    local surl="" si2
    for si2 in "${!STAT_NAMES[@]}"; do
      [[ ${STAT_NAMES[si2]} == "$nm" || ( $nm == clean && ${STAT_NAMES[si2]} == cleanliness ) ]] || continue
      stat_detail_info "$1" "$si2"; surl=$D_URL; break
    done
    local row="" labc=$MU
    (( k == dsel )) && labc="${IN}${C_BOLD}"   # Tab-inspected stat pops
    if [[ $k == 0 ]]; then row+="$(osc8 "$surl" "${IN}${C_BOLD}$(padw "$G_HEART $nm" 12)${RS}")"
    elif [[ $nm == health ]]; then row+="$(osc8 "$surl" "${labc}health${RS}${FA} self ${RS}")"
    else row+="$(osc8 "$surl" "${labc}$(printf '%-12s' "$nm")${RS}")"; fi
    if (( spark_w > 0 )); then
      if [[ -n $hist ]]; then
        local -a hv=($hist)
        local nb=$spark_w
        (( ${#hv[@]} < nb )) && nb=${#hv[@]}
        local bsz=$(( (${#hv[@]} + nb - 1) / nb ))
        local pts="" bi bj s c
        for ((bi=0; bi<nb; bi++)); do
          s=0; c=0
          for ((bj=bi*bsz; bj<(bi+1)*bsz && bj<${#hv[@]}; bj++)); do s=$((s + hv[bj])); c=$((c + 1)); done
          (( c > 0 )) && pts+="$(( s / c )) "
        done
        dspark "${pts% }"; row+="$DSP"
        (( nb < spark_w )) && row+="$(repeat_str " " $((spark_w - nb)))"
      else row+="${FA}$(repeat_str "·" "$spark_w")${RS}"; fi
      row+=" "
    fi
    local sw=$(( spark_w > 0 ? spark_w + 1 : 0 )) rlen
    if [[ $nm == health && -z $v ]]; then
      row+="${FA}─ private · by design${RS}"
      rlen=$(( lab_w + sw + 21 ))
    else
      dmeter "${v:-0}" "$cells" "$frozen"
      row+="$DM $(dval "${v:-0}" "$frozen")"
      rlen=$(( lab_w + sw + cells + 1 + 3 + frozen ))
    fi
    if (( k == dsel )); then
      # inspected row gets the soft highlight (same as the friends table)
      local selbg=$'\e[48;2;22;35;58m'
      local pad3=$(( viw - rlen )); (( pad3 < 0 )) && pad3=0
      row="${selbg}${row//$'\e[0m'/$'\e[0m'${selbg}}$(repeat_str " " "$pad3")"$'\e[49m'
      rlen=$viw
    fi
    scr_put "$vr" "$vx" "$rlen" "$row"
    vr=$((vr + 1))
    if [[ $k == 0 ]]; then
      scr_put "$vr" "$vx" "$viw" "$(fgt "$RGB_SEP")$(repeat_str "╌" "$viw")${RS}"
      vr=$((vr + 1))
    fi
  done
  if (( dsel >= 0 )); then
    # Tab inspector: what this stat tracks and why it has this score (§5.4/P2)
    local dnm=${vnames[dsel]} didx=-1 si3
    for si3 in "${!STAT_NAMES[@]}"; do
      if [[ ${STAT_NAMES[si3]} == "$dnm" || ( $dnm == clean && ${STAT_NAMES[si3]} == cleanliness ) ]]; then
        didx=$si3; break
      fi
    done
    if (( didx >= 0 )); then
      stat_detail_info "$1" "$didx"
      local dv=${P[${vkeys[dsel]}]:-—}
      local dt="${dnm} ${dv} — ${D_WHY} · src: ${D_SRC}${D_URL:+ · ↵ opens github}"
      local it="${G_SEL} $(marquee "$dt" $((viw - 2)))"
      scr_put $((pv_top + pv_h - 2)) "$vx" ${#it} "$(osc8 "$D_URL" "${MU}${it}${RS}")"
    fi
  else
    insight_text "$1"
    if [[ -n $INSIGHT ]]; then
      local it; it="${G_SEL} $(marquee "$INSIGHT" $((viw - 2)))"
      scr_put $((pv_top + pv_h - 2)) "$vx" ${#it} "${FA}${it}${RS}"
    fi
  fi

  # ── activity panel ──
  panel_frame $act_top 0 "$COLS" "$act_h" "$BR_ACT" "activity · ${P[ACT_SRC]:-events}/day · 60d" "g"
  local g_rows=$(( act_h - 4 ))          # borders + axis + meta
  local nd=$(( (COLS - 4) / 2 )); (( nd > 60 )) && nd=60
  build_graph "${P[EVDAYS]:-0}" "${P[EV_PEAK]:-1}" "${P[BASE_PD_X100]:-100}" "$nd" "$g_rows" \
              "${P[GAP_IDX]:-}" "${P[GAP_DAYS]:-}" "${P[MERGE_IDX]:--1}" "${P[MERGE_NUM]:-}" \
              "${P[MERGE_URL]:-}"
  local gx=2 r
  for ((r=0; r<g_rows; r++)); do
    scr_put $((act_top + 1 + r)) "$gx" $((nd * 2)) "${DGRAPH_LINES[r]}"
  done
  # baseline label at graph right edge (mockup .baseline .bl)
  local bl_lbl="┈ 90d baseline · $(( ${P[BASE_PD_X100]:-100} / 100 )).$(( (${P[BASE_PD_X100]:-100} % 100) / 10 ))"
  if (( gx + nd * 2 + ${#bl_lbl} + 2 < COLS - 2 )); then
    scr_put $((act_top + 1 + DGRAPH_BASEROW)) $((gx + nd * 2 + 1)) ${#bl_lbl} "$(fgt "$RGB_ORANGE")${C_DIM}${bl_lbl}${RS}"
  fi
  # axis: five labels spread like the mockup (-60d -45d -30d -15d today)
  local axis_row=$((act_top + act_h - 3)) meta_row=$((act_top + act_h - 2))
  local q
  for q in 0 1 2 3; do
    local lb="-$(( nd - nd * q / 4 ))d"
    scr_put "$axis_row" $(( gx + (nd * 2 - 6) * q / 4 )) ${#lb} "${FA}${lb}${RS}"
  done
  scr_put "$axis_row" $((gx + nd * 2 - 5)) 5 "${FA}today${RS}"
  local meta_full="today ${P[EV_TODAY]:-0}   peak ${P[EV_PEAK]:-0}   active ${P[ACTIVE21]:-0}/21d → fitness ${P[FITNESS]:-0}   rhythm beats volume — baseline is yours, not global"
  if (( ${#meta_full} <= COLS - 4 )); then
    scr_put "$meta_row" "$gx" ${#meta_full} "${MU}today ${IN}${C_BOLD}${P[EV_TODAY]:-0}${RS}${MU}   peak ${IN}${C_BOLD}${P[EV_PEAK]:-0}${RS}${MU}   active ${IN}${C_BOLD}${P[ACTIVE21]:-0}/21d${RS}${MU} → fitness ${P[FITNESS]:-0}   ${RS}${FA}rhythm beats volume — baseline is yours, not global${RS}"
  else
    local meta_p; meta_p=$(marquee "$meta_full" $((COLS - 4)))
    scr_put "$meta_row" "$gx" ${#meta_p} "${MU}${meta_p}${RS}"
  fi

  # ── friends panel (self only — on a friend, their feed takes the row) ──
  if [[ $self == 1 ]]; then
  panel_frame $ff_top 0 "$pw" "$ff_h" "$BR_FR" "friends · ${#FR_LOGINS[@]}" "f"
  local fx=2 frow=$((ff_top + 1))
  # columns shrink before any disappears: login and name give ground first,
  # lvl (kid/adult/elder) and the happy meter stay at every width
  local finner=$(( pw - 4 ))
  local login_w=14 name_w=10 lvl_w=7
  (( finner < 56 )) && { login_w=10; name_w=8; }
  (( finner < 48 )) && name_w=6
  (( finner < 38 )) && name_w=0
  (( finner < 32 )) && lvl_w=0
  # header: one clipped segment per column — nothing may cross a border
  dh_put() { local hx2=$1 htx=$2 hc=${3:-$FA}
    (( hx2 + ${#htx} <= finner )) || return 0
    scr_put "$frow" $(( fx + hx2 )) ${#htx} "${hc}${htx}${RS}"
  }
  dh_put 0 "login"
  dh_put "$login_w" "pet"
  (( lvl_w > 0 )) && dh_put $(( login_w + 5 + name_w )) "lvl"
  dh_put $(( login_w + 5 + name_w + lvl_w )) "${G_HEART} happy"
  dh_put $(( login_w + 5 + name_w + lvl_w + 13 )) "state"
  frow=$((frow + 1))
  # rows breathe when the panel can still show everyone double-spaced
  local fpitch=1
  (( ${#FR_SORTED[@]} > 0 && ff_top + ff_h - 1 - frow >= 2 * ${#FR_SORTED[@]} - 1 )) && fpitch=2
  if (( ${#FR_SORTED[@]} == 0 )); then
    scr_put "$frow" "$fx" $((pw - 5)) "${MU}$(trunc "Follow someone on GitHub and their pet appears here." $((pw - 5)))${RS}"
  fi
  # scrolling viewport (session view state, not pet state): the window
  # follows the tab cursor, wrap-around selection makes it endless
  local fcap=0 fr2=$frow fn=${#FR_SORTED[@]}
  while (( fr2 < ff_top + ff_h - 1 )); do fcap=$((fcap + 1)); fr2=$((fr2 + fpitch)); done
  (( SEL_FRIEND < ${FR_OFF:-0} )) && FR_OFF=$SEL_FRIEND
  (( SEL_FRIEND >= ${FR_OFF:-0} + fcap )) && FR_OFF=$(( SEL_FRIEND - fcap + 1 ))
  (( ${FR_OFF:-0} > fn - fcap )) && FR_OFF=$(( fn - fcap ))
  (( ${FR_OFF:-0} < 0 )) && FR_OFF=0
  if (( fn > fcap )); then
    local fend=$(( FR_OFF + fcap )); (( fend > fn )) && fend=$fn
    local fhint="↕ $(( FR_OFF + 1 ))-${fend}/${fn}"
    dh_put $(( finner - ${#fhint} )) "$fhint" "$MU"
  fi
  for i in "${!FR_SORTED[@]}"; do
    (( i < ${FR_OFF:-0} )) && continue
    (( frow >= ff_top + ff_h - 1 )) && break
    local login=${FR_SORTED[i]} rowd=${FRROW[${FR_SORTED[i]}]:-}
    # flush rows — selection reads from the tint + the blue bold login
    local logc=$IN
    (( i == SEL_FRIEND )) && logc="$(fgt "$RGB_BLUE")${C_BOLD}"
    local line=""
    if [[ -z $rowd ]]; then
      line="$(osc8 "https://github.com/$login" "${logc}$(printf "%-${login_w}s" "$(trunc "$login" "$login_w")")${RS}")${FA}···${RS}"
      scr_put "$frow" "$fx" $((login_w + 3)) "$line"
    else
      local pname=${rowd%%|*} r2=${rowd#*|}
      local mini=${r2%%|*} r3=${r2#*|}
      local c256=${r3%%|*} r4=${r3#*|}
      local happy=${r4%%|*} r5=${r4#*|}
      local state=${r5%%|*} r6=${r5#*|}
      local stage=${r6%%|*}
      local vis
      local glyph=$mini dispname=$pname
      [[ $state == hib:* ]] && glyph="(-)"      # cocooned, face hidden
      if [[ $state == egg:* ]]; then glyph="(${G_SPARK})"; dispname="—"; fi
      line="$(osc8 "https://github.com/$login" "${logc}$(printf "%-${login_w}s" "$(trunc "$login" "$login_w")")${RS}")"
      vis=$login_w
      line+="$(fg "$c256")$(padw "$glyph" 5)${RS}"
      vis=$(( vis + 5 ))
      if (( name_w > 0 )); then
        line+="${MU}$(padw "$(marquee "$dispname" $((name_w - 1)) "$i")" "$name_w")${RS}"
        vis=$(( vis + name_w ))
      fi
      if (( lvl_w > 0 )); then
        line+="${MU}$(padw "$(trunc "$stage" $((lvl_w - 1)))" "$lvl_w")${RS}"
        vis=$(( vis + lvl_w ))
      fi
      local remv=$(( finner - vis ))
      case $state in
        hib:*)
          local htxt="${G_ZZZ} hibernating · ${state#hib:}d"
          (( remv < ${#htxt} + 13 )) && htxt="${G_ZZZ} hib · ${state#hib:}d"
          if (( remv >= ${#htxt} + 13 )); then
            line+="${FA}$(padw "—" 13)${RS}"; vis=$((vis + 13)); remv=$((remv - 13))
          fi
          htxt=$(trunc "$htxt" "$remv")
          line+="$(fgt "$RGB_ICE")${htxt}${RS}"
          vis=$(( vis + ${#htxt} )) ;;
        egg:*)
          local etxt="hatches in ${state#egg:}d"
          if (( remv >= ${#etxt} + 13 )); then
            line+="${FA}$(padw "—" 13)${RS}"; vis=$((vis + 13)); remv=$((remv - 13))
          fi
          etxt=$(trunc "$etxt" "$remv")
          line+="$(fgt "$RGB_YELLOW")${etxt}${RS}"
          vis=$(( vis + ${#etxt} )) ;;
        *)
          local hv=${happy:-0}
          if (( remv >= 8 + ${#hv} )); then
            dmeter "$hv" 8
            local hrgb=$RGB_GREEN
            (( hv < 50 )) && hrgb=$RGB_YELLOW
            (( hv < 20 )) && hrgb=$RGB_RED
            line+="${DM}$(fgt "$hrgb")${C_BOLD}${hv}${RS}"
            vis=$(( vis + 8 + ${#hv} ))
          fi ;;
      esac
      # selected row: soft blue highlight, like the mockup tr.sel
      if (( i == SEL_FRIEND )); then
        local selbg=$'\e[48;2;22;35;58m'
        local pad2=$(( pw - 4 - vis )); (( pad2 < 0 )) && pad2=0
        line="${selbg}${line//$'\e[0m'/$'\e[0m'${selbg}}$(repeat_str " " "$pad2")"$'\e[49m'
        vis=$(( pw - 4 ))
      fi
      scr_put "$frow" "$fx" "$vis" "$line"
    fi
    frow=$((frow + fpitch))
  done
  fi

  # ── feed panel (full-width on a friend view) ──
  local feed_x=$((pw + 1)) feed_w=$((rw - 1)) ftitle="feed · live · ${TTL_FAST}s"
  if [[ $self != 1 ]]; then feed_x=0; feed_w=$COLS; ftitle="feed · cache · 5m"; fi
  panel_frame $ff_top "$feed_x" "$feed_w" "$ff_h" "$BR_FEED" "$ftitle" "e"
  local fex=$((feed_x + 2)) fer=$((ff_top + 1))
  local ent fn=0
  DFEED_VIS=0 MFEED_URL=""
  for ent in "${DFEED[@]}"; do
    (( fer >= ff_top + ff_h - 2 )) && break
    local t=${ent%%|*} e2=${ent#*|}
    local tag=${e2%%|*} e3=${e2#*|}
    local tx=${e3%%|*} e4=${e3#*|}
    local fxv=$e4 furl=""
    if [[ $e4 == *"|"* ]]; then fxv=${e4%%|*}; furl=${e4#*|}; fi
    local trgb; trgb=$(feed_tag_rgb "$tag")
    local avail=$(( feed_w - 4 - 7 - ${#tag} - 2 - 1 - ${#fxv} - 1 ))
    tx=$(marquee "$tx" "$avail" "$fer")
    # white-hot facts like the mockup (.fev .tx b): PR numbers, repos, refs
    local txc=$tx
    local WH2; WH2=$(fgt "255;255;255")
    if [[ $tx =~ ^PR\ (#[0-9]+)\ merged\ in\ (.+)$ ]]; then
      txc="PR ${WH2}${C_BOLD}${BASH_REMATCH[1]}${RS}$(fgt "$RGB_VOICE") merged in ${WH2}${C_BOLD}${BASH_REMATCH[2]}${RS}"
    elif [[ $tx == *" · "* ]]; then
      txc="${tx%% · *} · ${WH2}${C_BOLD}${tx#* · }${RS}"
    else
      # scrolled text: light up any visible refs
      local VXHL
      vx_hl "$tx" '[A-Za-z0-9._/-]*#[0-9]+' "${WH2}${C_BOLD}" $'\e[22m'"$(fgt "$RGB_VOICE")"
      txc=$VXHL
    fi
    # the whole tag+text is one hyperlink to the PR / issue / alert (OSC 8)
    local FCHIP; feed_tag_chip "$tag"
    local body="${FCHIP} $(fgt "$RGB_VOICE")${txc}${RS}"
    local line="${FA}$(printf '%-7s' "$t")${RS}$(osc8 "$furl" "$body")"
    local vis=$(( 7 + ${#tag} + 2 + 1 + ${#tx} ))
    if [[ -n $fxv ]]; then line+=" $(fgt "$RGB_GREEN")${C_BOLD}${fxv}${RS}"; vis=$((vis + 1 + ${#fxv})); fi
    if (( fn == ${MFEED_SEL:--1} )); then   # tab-inspected entry: purple tint
      MFEED_URL=$furl
      local fselbg=$'\e[48;2;30;24;44m'
      local fpad=$(( feed_w - 4 - vis )); (( fpad < 0 )) && fpad=0
      line="${fselbg}${line//$'\e[0m'/$'\e[0m'${fselbg}}$(repeat_str " " "$fpad")"$'\e[49m'
      vis=$(( feed_w - 4 ))
    fi
    scr_put "$fer" "$fex" "$vis" "$line"
    fer=$((fer + 1)); fn=$((fn + 1))
  done
  DFEED_VIS=$fn
  if (( fer < ff_top + ff_h - 1 )); then
    local note="poll: ${TTL_FAST}s · ETag · 304s are free — being alive costs ~0 rate limit"
    note=$(marquee "$note" $((feed_w - 4)) 5)
    scr_put $((ff_top + ff_h - 2)) "$fex" ${#note} "${FA}${note}${RS}"
  fi


  # ── footer ──
  local -a fkeys=("f friends" "s stats" "g graph" "e feed" "tab inspect" "c compare" "r refresh" "d cozy" "? help" "q quit")
  [[ $self != 1 ]] && fkeys=("s stats" "g graph" "e feed" "tab inspect" "c compare" "r refresh" "esc back" "? help" "q quit")
  dense_footer "$ftr" "${fkeys[@]}"

  scr_emit
  # glee flies on the z-layer from the feed card, over every panel, to the
  # pet card (🍕 + nom on merges · ✦ on medals/followers) — spliced after
  # compositing, so it passes over all the text
  if [[ $self == 1 ]]; then
    local gf
    local gsy=$(( ff_top + ff_h - 2 ))
    for gf in "${FEED_FLOATERS[@]}"; do
      local gage=${gf%%|*} grest=${gf#*|}
      local gfrac=${grest%%|*} grest2=${grest#*|}
      local gw2=${grest2%%|*} grest3=${grest2#*|}
      local gch=${grest3%%|*} gcol=${grest3#*|}
      (( gage < 0 )) && continue
      local gt=$(( gage * 100 / 16 )); (( gt > 100 )) && gt=100
      local gsx=$(( feed_x + 3 + gfrac * (feed_w - 10) / 100 ))
      local grow=$(( gsy + (GLEE_TY - gsy) * gt / 100 ))
      local gx2=$(( gsx + (GLEE_TX - gsx) * gt / 100 + (gage + gfrac) % 3 - 1 ))
      (( grow < 1 || grow >= LINES - 1 )) && continue
      screen_overlay "$grow" "$gx2" "${gcol}${gch}" "$gw2"
    done
    # friend milestones: confetti (hatch) and sparkles (level-up) rise from
    # the friends card, straight up over every panel
    local hsy=$(( ff_top + ff_h - 2 ))
    for gf in "${FR_FLOATERS[@]}"; do
      local gage=${gf%%|*} grest=${gf#*|}
      local gfrac=${grest%%|*} grest2=${grest#*|}
      local gw2=${grest2%%|*} grest3=${grest2#*|}
      local gch=${grest3%%|*} gcol=${grest3#*|}
      (( gage < 0 )) && continue
      local grow=$(( hsy - gage / 2 ))
      (( grow < 1 || grow >= LINES - 1 )) && continue
      local gx2=$(( 2 + gfrac * (pw - 8) / 100 + (gage / 2 + gfrac) % 3 - 1 ))
      (( gx2 < 1 )) && gx2=1
      screen_overlay "$grow" "$gx2" "${gcol}${gch}" "$gw2"
    done
  fi
  # a perfect 100: three hearts swirl around the pet's head on the z-layer
  if (( ${P[HAPPINESS]:-0} >= 100 )) && [[ $ANIM_STATE == idle || $ANIM_STATE == celebrate || $ANIM_STATE == eat ]]; then
    local -a odx=(6 5 3 0 -3 -5 -6 -5 -3 0 3 5)
    local -a ody=(0 1 2 2 2 1 0 -1 -2 -2 -2 -1)
    local hi2
    for hi2 in 0 1 2; do
      local hph=$(( (TICK / 2 + hi2 * 4) % 12 ))
      local hrr=$(( GLEE_HY + ody[hph] ))
      local hcc=$(( GLEE_HX + odx[hph] ))
      (( hrr <= pv_top || hrr >= ground )) && continue
      (( hcc < 1 || hcc > pw - 2 )) && continue
      screen_overlay "$hrr" "$hcc" "${C_HEARTS}${G_HEART_FLOAT}"
    done
  fi
  # fetch (PR merged): the pixel ball rides the z-layer — thrown across the
  # stage, then carried home in the pet's mouth (anim_update owns the story;
  # FETCH_BX is a stage-center-relative column, "M" pins it to the mouth)
  if [[ $self == 1 && -n ${FETCH_BX:-} && -n $PIX_MODE && -n ${PIXF[ball/idle_1]:-} ]]; then
    pix_palette ball "${PIXREF[ball]}" 0
    pix_render ball idle_1 0
    local bw2=$PIXOUT_W bh2=$PIXOUT_H brow bcol bi2
    local brlo=$(( stage_top + 1 )) brhi=$ground bchi=$(( pw - 1 ))
    if [[ $FETCH_BX == T* ]]; then
      # the throw: the merge hurls the ball out of the feed card, across
      # every panel on the z-layer, arcing down to the landing spot
      local tb=${FETCH_BX#T} tfrac
      tfrac=$(( (tb + 1) * 25 ))
      local tx0=$(( feed_x + 4 )) ty0=$ff_top
      local tx1=$(( pix0 + piw / 2 + ${FETCH_LAND:-14} - bw2 / 2 ))
      local ty1=$(( ground - bh2 ))
      bcol=$(( tx0 + (tx1 - tx0) * tfrac / 100 ))
      brow=$(( ty0 + (ty1 - ty0) * tfrac / 100 - tfrac * (100 - tfrac) / 1200 ))
      brlo=1; brhi=$(( LINES - 1 )); bchi=$(( COLS - 1 ))
    elif [[ $FETCH_BX == M ]]; then
      bcol=$(( GLEE_TX + 2 )); brow=$(( GLEE_TY ))
    else
      bcol=$(( pix0 + piw / 2 + FETCH_BX - bw2 / 2 ))
      brow=$(( ground - bh2 - ${FETCH_BY:-0} ))
    fi
    for ((bi2=0; bi2<bh2; bi2++)); do
      local br2=$(( brow + bi2 ))
      (( br2 < brlo || br2 >= brhi )) && continue
      (( bcol < 1 || bcol + bw2 > bchi )) && continue
      screen_overlay "$br2" "$bcol" "${PIXOUT[bi2]}" "$bw2"
    done
  fi
  # sleeping dims the whole screen one step (ux-spec §9 state treatments)
  if [[ $ANIM_STATE == sleep ]]; then
    local si
    for si in "${!SCREEN[@]}"; do
      SCREEN[si]="${C_DIM}${SCREEN[si]//$'\e[0m'/$'\e[0;2m'}${RS}"
    done
  fi
}

# ── dense compare (gitagotchi-compare.html): one purple panel; the pets face
# each other over a shared groundline, every mirrored bar is colored by WHOSE
# it is (your linguist color vs theirs), ◂/▸ green marks the higher side and
# the printed number carries magnitude. Curiosity + wisdom sit below a dashed
# rule as the slow stats; health is structurally absent, not shown empty. ────
rgb_dim() { # "r;g;b" → the loser's 45%-opacity fill from the mockup
  local r=${1%%;*} rest=${1#*;}
  local g=${rest%%;*} b=${rest#*;}
  printf '%d;%d;%d' $((r * 45 / 100)) $((g * 45 / 100)) $((b * 45 / 100))
}
cmp_bar() { # value cells rgb dim frozen anchor_right → CBAR (visible = cells)
  local v=$1 n=$2 rgb=$3 dim=$4 fro=$5 right=$6
  local fill=$(( (v * n + 50) / 100 ))
  (( fill < 0 )) && fill=0; (( fill > n )) && fill=$n
  (( v > 0 && fill == 0 )) && fill=1
  local c=$rgb
  (( fro )) && c=$RGB_ICE          # hibernation freezes the fill ice-blue
  (( dim )) && c=$(rgb_dim "$c")
  local fc tc
  fc=$(fgt "$c"); tc=$(fgt "$RGB_TRACK")
  # lower-half fill: the top half of every cell stays background, so stacked
  # rows read as padded like the mockup's bordered bars. Track is a thin
  # baseline — still a distinct glyph, so the --snapshot plain text keeps the
  # comparison legible once the colors are stripped (§5.7: paste anywhere)
  local fch="▄" ech="▁"
  [[ $TIER == A ]] && { fch="#"; ech="-"; }
  if (( right )); then             # your bar grows toward the center
    CBAR="${tc}$(repeat_str "$ech" $((n - fill)))${fc}$(repeat_str "$fch" "$fill")${RS}"
  else                             # theirs grows away from it
    CBAR="${fc}$(repeat_str "$fch" "$fill")${tc}$(repeat_str "$ech" $((n - fill)))${RS}"
  fi
}
cmp_bond() { # me_assoc friend_assoc → BOND (status label), BOND_N (count)
  # relationship = how much you actually talk: comment/review events on each
  # other's repos over the events window (~90d), both directions summed from
  # the two COMMS_RAW ledgers. Derived, never stored — drift is honest.
  local -n QA=$1 QB=$2
  BOND_N=0
  local pair raw who
  for pair in "${QA[COMMS_RAW]:-}|${QB[LOGIN]:-}" "${QB[COMMS_RAW]:-}|${QA[LOGIN]:-}"; do
    raw=${pair%|*}; who=${pair##*|}
    [[ -z $raw || -z $who ]] && continue
    local seg rest=$raw
    while [[ -n $rest ]]; do
      seg=${rest%%;*}
      if [[ $seg == "$rest" ]]; then rest=""; else rest=${rest#*;}; fi
      [[ ${seg%%|*} == "$who" ]] && BOND_N=$(( BOND_N + ${seg##*|} ))
    done
  done
  if   (( BOND_N == 0 )); then BOND="distant orbits"
  elif (( BOND_N < 3 ));  then BOND="acquaintances"
  elif (( BOND_N < 8 ));  then BOND="pen pals"
  elif (( BOND_N < 20 )); then BOND="buddies"
  else BOND="partners in crime"; fi
}
cmp_medal_parse() { # raw codes_ref names_ref tiers_ref
  local raw=$1
  local -n CO=$2 NA=$3 TI=$4
  CO=() NA=() TI=()
  local m
  while [[ -n $raw ]]; do
    m=${raw%%;*}
    if [[ $m == "$raw" ]]; then raw=""; else raw=${raw#*;}; fi
    [[ -z $m ]] && continue
    NA+=("${m%%|*}"); TI+=("${m##*|}")
    CO+=("$(medal_code "${m%%|*}")")
  done
}
cmp_medal_chips() { # codes_ref tiers_ref "shared codes" → CHIPS_C CHIPS_P
  local -n CO=$1 TI=$2
  local shared=" $3 "
  CHIPS_C="" CHIPS_P=""
  local i lb col
  for i in "${!CO[@]}"; do
    lb=${CO[i]}
    [[ ${TI[i]} =~ ^[0-9]+$ ]] && (( TI[i] > 1 )) && lb+=" ×${TI[i]}"
    # mockup .medal: gold label in a dimmed-gold border; .medal.shared green
    col=$RGB_YELLOW
    [[ $shared == *" ${CO[i]} "* ]] && col=$RGB_GREEN
    CHIPS_C+="$(fgt "$(rgb_dim "$col")")[$(fgt "$col")${C_BOLD}${lb}${RS}$(fgt "$(rgb_dim "$col")")]${RS}"
    CHIPS_P+="[${lb}]"
  done
}
draw_compare_dense() { # me_assoc friend_assoc
  local -n DM1=$1
  local -n DF1=$2
  scr_reset
  local MU FA IN VO GC
  MU=$(fgt "$RGB_MUTED"); FA=$(fgt "$RGB_FAINT"); IN=$(fgt "$RGB_INK")
  VO=$(fgt "$RGB_VOICE"); GC="$(fgt "$RGB_GREEN")${C_BOLD}"
  local SEPC; SEPC=$(fgt "$RGB_SEP")
  local mrgb frgb MC2 FC2
  mrgb=$(hex_to_rgb "${DM1[COLOR_HEX]:-#dea584}")
  frgb=$(hex_to_rgb "${DF1[COLOR_HEX]:-#f1e05a}")
  MC2=$(fgt "$mrgb"); FC2=$(fgt "$frgb")
  local mhib=${DM1[HIB]:-0} fhib=${DF1[HIB]:-0}
  local flog="@${DF1[LOGIN]}"

  # size ladder: breathing blanks go first, then the stage shrinks, then the
  # under-sections drop — every section shrinks before any disappears
  local avail=$(( LINES - 3 ))
  local stage_h=9 blanks=1 show_ins=1 show_under=1 show_health=1
  _cmp_need() {
    local n=$(( stage_h + 4 + 1 + 9 ))   # heads+ground · you/@ row · stat rows
    (( show_health )) && n=$((n + 1))
    (( show_under )) && n=$(( n + 6 + blanks ))
    (( show_ins ))   && n=$(( n + 5 + blanks ))
    printf '%s' "$n"
  }
  (( $(_cmp_need) > avail )) && blanks=0
  while (( $(_cmp_need) > avail && stage_h > 7 )); do stage_h=$((stage_h - 1)); done
  (( $(_cmp_need) > avail )) && show_ins=0
  (( $(_cmp_need) > avail )) && show_under=0
  (( $(_cmp_need) > avail )) && show_health=0
  while (( $(_cmp_need) > avail && stage_h > 5 )); do stage_h=$((stage_h - 1)); done
  local ph=$(( $(_cmp_need) + 2 )); (( ph > LINES - 1 )) && ph=$(( LINES - 1 ))
  panel_frame 0 0 "$COLS" "$ph" "$RGB_PURPLE" "compare" "c on any friend · esc back"

  # ── header strip: two identities facing off across the center ──
  local half=$(( COLS / 2 )) stage_end=$stage_h
  local side sidep
  for side in 0 1; do
    local px0 piw hib2 flip2 fr2 bl2 cc2
    local crgb
    if (( side == 0 )); then
      sidep=$1; px0=2; piw=$(( half - 3 )); hib2=$mhib; flip2=0; cc2=$MC2; crgb=$mrgb
      fr2=$ANIM_FRAME; bl2=${ANIM_BLINK:-0}
    else
      sidep=$2; px0=$(( half + 1 )); piw=$(( COLS - half - 3 )); hib2=$fhib; flip2=1; cc2=$FC2; crgb=$frgb
      fr2=idle_$(( (TICK / 2) % 2 + 1 )); bl2=0
      (( TICK % 18 == 8 )) && bl2=1
      (( hib2 )) && fr2=hibernate_1
    fi
    local -n SP2=$sidep
    pet_compose "$sidep" "$fr2" "$bl2" 0 "$flip2"
    local petx=$(( px0 + (piw - PET_W) / 2 )); (( petx < px0 )) && petx=$px0
    local ptop=$(( stage_end - PET_H + 1 )) i2 skip2=0
    if (( ptop < 1 )); then skip2=$(( 1 - ptop )); ptop=1; fi
    for ((i2=skip2; i2<PET_H; i2++)); do
      scr_put $((ptop + i2 - skip2)) "$petx" "$PET_W" "${PET_LINES[i2]}"
    done
    local nm=${SP2[NAME]}
    scr_put $((stage_end + 1)) $(( px0 + (piw - ${#nm}) / 2 )) ${#nm} "${IN}${C_BOLD}${nm}${RS}"
    local who="@${SP2[LOGIN]} · $(tr '[:upper:]' '[:lower:]' <<<"${SP2[SPECIES_LABEL]:-${SP2[SPECIES]}}") · ${SP2[STAGE]:-} · est. ${SP2[CREATED_YEAR]:-}"
    who=$(trunc "$who" "$piw")
    scr_put $((stage_end + 2)) $(( px0 + (piw - ${#who}) / 2 )) ${#who} "${MU}${who}${RS}"
    # linguist chip: dimmed brackets stand in for the mockup's 40%-opacity
    # border (#dea58466), the text wears the full owner color
    local lang; lang=$(tr '[:upper:]' '[:lower:]' <<<"${SP2[TOP_LANG]:-?}")
    local chip="■ ${lang} $(tr '[:upper:]' '[:lower:]' <<<"${SP2[COLOR_HEX]:-}")"
    chip=$(trunc "$chip" $(( piw - 4 )))
    local cbd; cbd=$(fgt "$(rgb_dim "$crgb")")
    scr_put $((stage_end + 3)) $(( px0 + (piw - ${#chip} - 4) / 2 )) $(( ${#chip} + 4 )) \
      "${cbd}[${RS} ${cc2}${chip}${RS} ${cbd}]${RS}"
  done
  scr_put $(( stage_end - 2 )) $(( half - 1 )) 2 "${IN}${C_BOLD}vs${RS}"
  # relationship status from the summed bond ledgers; falls back to the
  # plain word when the label wouldn't fit between the pets
  local BOND BOND_N
  cmp_bond "$1" "$2"
  (( ${#BOND} > half - 27 )) && BOND="friends"
  scr_put $(( stage_end - 1 )) $(( half - ${#BOND} / 2 )) ${#BOND} "${FA}${BOND}${RS}"
  # the follow date isn't in the API, so "since" is the honest lower bound:
  # the younger account's est. year — no friendship predates it
  local sy=${DM1[CREATED_YEAR]:-} fy=${DF1[CREATED_YEAR]:-}
  if [[ $sy =~ ^[0-9]+$ && $fy =~ ^[0-9]+$ ]]; then
    local since="since $(( sy > fy ? sy : fy ))"
    scr_put "$stage_end" $(( half - ${#since} / 2 )) ${#since} "${FA}${since}${RS}"
  fi
  local gy=$(( stage_end + 4 ))
  scr_put "$gy" 3 $(( COLS - 6 )) "${SEPC}$(repeat_str "┄" $((COLS - 6)))${RS}"

  # ── mirrored stat rows: val ◂ bar(yours) · label · bar(theirs) ▸ val ──
  local rowsw=$(( COLS - 8 )); (( rowsw > 100 )) && rowsw=100
  local bw=$(( (rowsw - 23) / 2 )); (( bw < 8 )) && bw=8
  rowsw=$(( 23 + 2 * bw ))
  local rx0=$(( (COLS - rowsw) / 2 ))
  local x_bar_l=$(( rx0 + 6 )) x_lab=$(( rx0 + 7 + bw )) x_bar_r=$(( rx0 + 17 + bw ))
  scr_put $(( gy + 1 )) "$rx0" 3 "${FA}you${RS}"
  scr_put $(( gy + 1 )) $(( rx0 + rowsw - ${#flog} )) ${#flog} "${FA}${flog}${RS}"
  local keys=(HAPPINESS HUNGER ENERGY FITNESS SOCIAL CLEAN - CURIOSITY WISDOM)
  local names=(happy hunger energy fitness social clean - curiosity wisdom)
  local ry=$(( gy + 2 )) k2
  for k2 in "${!keys[@]}"; do
    if [[ ${keys[k2]} == - ]]; then
      scr_put "$ry" "$rx0" "$rowsw" "${SEPC}$(repeat_str "╌" "$rowsw")${RS}"
      ry=$((ry + 1)); continue
    fi
    local av=${DM1[${keys[k2]}]:-0} bv=${DF1[${keys[k2]}]:-0}
    local awin=0 bwin=0
    (( av >= bv )) && awin=1
    (( bv > av )) && bwin=1
    local ac=$MU bc=$MU
    (( awin )) && ac=$IN
    (( bwin )) && bc=$IN
    scr_put "$ry" "$rx0" 3 "${ac}${C_BOLD}$(printf '%3s' "$av")${RS}"
    (( awin )) && scr_put "$ry" $((rx0 + 4)) 1 "${GC}${G_CMPW}${RS}"
    cmp_bar "$av" "$bw" "$mrgb" $((1 - awin)) "$mhib" 1
    scr_put "$ry" "$x_bar_l" "$bw" "$CBAR"
    local lb=${names[k2]}
    scr_put "$ry" $(( x_lab + (9 - ${#lb}) / 2 )) ${#lb} "${MU}${lb}${RS}"
    cmp_bar "$bv" "$bw" "$frgb" $((1 - bwin)) "$fhib" 0
    scr_put "$ry" "$x_bar_r" "$bw" "$CBAR"
    (( bwin )) && scr_put "$ry" $(( x_bar_r + bw + 1 )) 1 "${GC}${G_SEL}${RS}"
    scr_put "$ry" $(( x_bar_r + bw + 3 )) 3 "${bc}${C_BOLD}$(printf '%-3s' "$bv")${RS}"
    ry=$((ry + 1))
  done
  if (( show_health )); then
    local hn="health — private on both sides, by design"
    local hx=$(( x_bar_l + bw - ${#hn} )); (( hx < rx0 )) && hx=$rx0
    scr_put "$ry" "$hx" ${#hn} "${FA}${hn}${RS}"
    ry=$((ry + 1))
  fi

  # ── under-sections: dual 14-day mini-chart · medal shelves ──
  if (( show_under )); then
    ry=$(( ry + blanks ))
    local ubw=$(( (rowsw - 2) / 2 )) ux2 uw2
    ux2=$(( rx0 + ubw + 2 )); uw2=$(( rowsw - ubw - 2 ))
    local mtitle="medal shelves · shared medals in green"
    (( ${#mtitle} + 8 > uw2 )) && mtitle="medals · shared in green"
    PF_TITLE_RGB=$RGB_MUTED
    panel_frame "$ry" "$rx0" "$ubw" 6 "$RGB_SEP" "last 14 days · events/day" ""
    PF_TITLE_RGB=$RGB_MUTED
    panel_frame "$ry" "$ux2" "$uw2" 6 "$RGB_SEP" "$mtitle" ""
    # both series over one scale; a column pair per day, you then them
    local -a mev=(${DM1[EVDAYS]:-0}) fev=(${DF1[EVDAYS]:-0})
    local -a m14=("${mev[@]: -14}") f14=("${fev[@]: -14}")
    while (( ${#m14[@]} < 14 )); do m14=(0 "${m14[@]}"); done
    while (( ${#f14[@]} < 14 )); do f14=(0 "${f14[@]}"); done
    local pk=1 v
    for v in "${m14[@]}" "${f14[@]}"; do (( v > pk )) && pk=$v; done
    local ciw=$(( ubw - 4 )) nd=14 pgw=1
    (( nd * 2 + nd - 1 > ciw )) && pgw=0
    (( nd * 2 > ciw )) && { nd=7; pgw=1; }
    (( nd * 2 + nd - 1 > ciw )) && pgw=0
    local r d cw=$(( nd * 2 + (nd - 1) * pgw ))
    for ((r=0; r<3; r++)); do
      local line="" pair vv cc3
      for ((d=0; d<nd; d++)); do
        local di=$d; (( nd == 7 )) && di=$(( d * 2 ))
        for pair in 0 1; do
          if (( pair == 0 )); then vv=${m14[di]:-0}; cc3=$MC2; else vv=${f14[di]:-0}; cc3=$FC2; fi
          local f8=$(( vv * 24 / pk - (2 - r) * 8 ))
          (( f8 < 0 )) && f8=0; (( f8 > 8 )) && f8=8
          if (( f8 == 0 )); then line+=" "
          else line+="${cc3}${EIGHTHS:f8:1}${RS}"; fi
        done
        (( pgw && d < nd - 1 )) && line+=" "
      done
      scr_put $((ry + 1 + r)) $(( rx0 + 2 )) "$cw" "$line"
    done
    local mbl=${DM1[BASE_PD_X100]:-0} fbl=${DF1[BASE_PD_X100]:-0}
    local lg1="you · baseline $((mbl / 100)).$(((mbl % 100) / 10))"
    local lg2="${flog} · baseline $((fbl / 100)).$(((fbl % 100) / 10))"
    if (( ${#lg1} + ${#lg2} + 6 > ciw )); then
      lg1="you $((mbl / 100)).$(((mbl % 100) / 10))"
      lg2="${flog} $((fbl / 100)).$(((fbl % 100) / 10))"
    fi
    scr_put $((ry + 4)) $(( rx0 + 2 )) $(( ${#lg1} + ${#lg2} + 6 )) \
      "${MC2}■${RS} ${FA}${lg1}${RS}  ${FC2}■${RS} ${FA}${lg2}${RS}"
    # medal shelves: outline chips, gold; the ones you share turn green
    local -a MAC MAN MAT MBC MBN MBT
    cmp_medal_parse "${DM1[MEDALS_RAW]:-}" MAC MAN MAT
    cmp_medal_parse "${DF1[MEDALS_RAW]:-}" MBC MBN MBT
    [[ ${DM1[MEDALS_OK]:-0} != 1 ]] && { MAC=(); MAN=(); MAT=(); }
    [[ ${DF1[MEDALS_OK]:-0} != 1 ]] && { MBC=(); MBN=(); MBT=(); }
    local shared="" shared_name="" only_f="" i j
    for i in "${!MAC[@]}"; do
      for j in "${!MBC[@]}"; do
        if [[ ${MAC[i]} == "${MBC[j]}" ]]; then
          shared+="${MAC[i]} "
          [[ -z $shared_name ]] && shared_name=${MAN[i]}
          break
        fi
      done
    done
    for j in "${!MBC[@]}"; do
      [[ " $shared" == *" ${MBC[j]} "* ]] && continue
      only_f=${MBN[j]}; break
    done
    local miw=$(( uw2 - 4 )) CHIPS_C CHIPS_P
    local sw=${#flog}
    (( sw > 10 )) && sw=10
    (( sw < 3 )) && sw=3
    local mrow
    for mrow in 0 1; do
      local sl="you" chc chp
      (( mrow == 1 )) && sl=$flog
      if (( mrow == 0 )); then cmp_medal_chips MAC MAT "$shared"
      else cmp_medal_chips MBC MBT "$shared"; fi
      chc=$CHIPS_C; chp=$CHIPS_P
      [[ -z $chp ]] && { chp="—"; chc="${FA}—${RS}"; }
      if (( sw + 1 + ${#chp} > miw )); then chp=$(trunc "$chp" $((miw - sw - 1))); chc="${MU}${chp}${RS}"; fi
      scr_put $((ry + 1 + mrow)) $(( ux2 + 2 )) $(( sw + 1 + ${#chp} )) \
        "${FA}$(printf "%-${sw}s" "$(trunc "$sl" "$sw")")${RS} ${chc}"
    done
    local mnote
    if [[ -n $shared_name ]]; then mnote="${shared_name} in common"
    else mnote="no medals in common yet"; fi
    [[ -n $only_f ]] && mnote+=" · ${flog} has ${only_f}"
    mnote=$(trunc "$mnote" "$miw")
    scr_put $((ry + 4)) $(( ux2 + 2 )) ${#mnote} "${FA}${mnote}${RS}"
    ry=$(( ry + 6 ))
  fi

  # ── what the pets noticed: three derived observations, dot = whose win ──
  if (( show_ins )); then
    ry=$(( ry + blanks ))
    PF_TITLE_RGB=$RGB_MUTED
    panel_frame "$ry" "$rx0" "$rowsw" 5 "$RGB_SEP" "what the pets noticed" ""
    local mn=${DM1[NAME]} fn2=${DF1[NAME]}
    local -a ins_rgb=() ins_b=() ins_r=()
    local me_e=${DM1[ENERGY]:-0} f_e=${DF1[ENERGY]:-0}
    if (( me_e == f_e )); then
      ins_rgb+=("$RGB_FAINT"); ins_b+=("evenly rested"); ins_r+=(" — energy ${me_e} apiece.")
    elif (( me_e > f_e )); then
      ins_rgb+=("$mrgb"); ins_b+=("${mn} is better rested"); ins_r+=(" — energy ${me_e} to ${fn2}'s ${f_e}.")
    else
      ins_rgb+=("$frgb"); ins_b+=("${fn2} is better rested"); ins_r+=(" — energy ${f_e} to ${mn}'s ${me_e}.")
    fi
    local mm7=${DM1[MERGES7]:-0} fm7=${DF1[MERGES7]:-0}
    if (( mm7 == fm7 )); then
      ins_rgb+=("$RGB_FAINT"); ins_b+=("even at the bowl"); ins_r+=(" — ${mm7} merges each this week.")
    else
      local wname wassoc lname lo hi
      if (( mm7 > fm7 )); then wname=$mn wassoc=$1 lname=$fn2 hi=$mm7 lo=$fm7
      else wname=$fn2 wassoc=$2 lname=$mn hi=$fm7 lo=$mm7; fi
      local -n WI=$wassoc
      local det=" — ${hi} merges to ${lname}'s ${lo} this week"
      if [[ ${WI[MERGE_AGO_H]:--1} =~ ^[0-9]+$ ]] && (( WI[MERGE_AGO_H] >= 0 )) && [[ -n ${WI[MERGE_NUM]:-} ]]; then
        local agoh=${WI[MERGE_AGO_H]} ago
        if (( agoh < 48 )); then ago="${agoh}h"; else ago="$((agoh / 24))d"; fi
        det+=" (#${WI[MERGE_NUM]} was ${ago} ago)"
      fi
      if (( mm7 > fm7 )); then ins_rgb+=("$mrgb"); else ins_rgb+=("$frgb"); fi
      ins_b+=("${wname} eats better"); ins_r+=("${det}.")
    fi
    local ma21=${DM1[ACTIVE21]:-0} fa21=${DF1[ACTIVE21]:-0}
    if (( ma21 == fa21 )); then
      ins_rgb+=("$RGB_FAINT"); ins_b+=("in step"); ins_r+=(" — both shipped ${ma21} of the last 21 days.")
    elif (( ma21 > fa21 )); then
      ins_rgb+=("$mrgb"); ins_b+=("${mn} is fitter")
      ins_r+=(" — shipped ${ma21} of the last 21 days to ${fn2}'s ${fa21}.")
    else
      ins_rgb+=("$frgb"); ins_b+=("${fn2} is fitter")
      ins_r+=(" — shipped ${fa21} of the last 21 days to ${mn}'s ${ma21}.")
    fi
    local ii
    for ii in 0 1 2; do
      local rest=${ins_r[ii]}
      local rmax=$(( rowsw - 4 - 2 - ${#ins_b[ii]} ))
      (( rmax < 0 )) && rmax=0
      rest=$(trunc "$rest" "$rmax")
      scr_put $((ry + 1 + ii)) $(( rx0 + 2 )) $(( 2 + ${#ins_b[ii]} + ${#rest} )) \
        "$(fgt "${ins_rgb[ii]}")■${RS} ${IN}${C_BOLD}${ins_b[ii]}${RS}${VO}${rest}${RS}"
    done
  fi

  # footer literally states the stance — no total is computed, on purpose
  local note="friendly rivalry, not a leaderboard — no total is computed, on purpose"
  (( COLS < 145 )) && note="friendly rivalry, not a leaderboard"
  DFOOT_RIGHT=$note
  dense_footer $((LINES - 1)) "↹ next friend" "↵ visit ${flog}" "s snapshot to stdout" "esc back"
  scr_emit
}

# FEED_RAW ("t|tag|tx|fx;;…") → DFEED[]
declare -a DFEED=()
dfeed_load() {
  DFEED=()
  local raw=$1
  while [[ $raw == *";;"* ]]; do
    DFEED+=("${raw%%;;*}")
    raw=${raw#*;;}
  done
  [[ -n $raw ]] && DFEED+=("$raw")
}