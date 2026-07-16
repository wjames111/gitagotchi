# gitagotchi — lib/render.sh
# Layout system (ux-spec §3), main-screen anatomy (§5.2), pet state gallery
# (§5.3), voice (§7). Buffer-based: draw_* fills SCREEN[], paint() flushes.

declare -a SCREEN
IW=0 SH=0   # inner width, stage height

paint() {
  local out=$'\e[H' l first=1
  for l in "${SCREEN[@]}"; do
    (( first )) && first=0 || out+=$'\n'
    out+="$l"$'\e[K'
  done
  out+=$'\e[J'
  printf '%s' "$out"
}

# ── row builder ─────────────────────────────────────────────────────────────
RP="" RC=""
rnew() { RP="" RC=""; }
radd() { # text [colorseq]
  RP+=$1
  if [[ -n ${2:-} ]]; then RC+="${2}${1}${RS}"; else RC+=$1; fi
}
rpad() { local need=$(( $1 - ${#RP} )); if (( need > 0 )); then local s; s=$(repeat_str " " "$need"); RP+=$s RC+=$s; fi; }
rpush() { rpad "$IW"; SCREEN+=("${C_CHROME}${B_V}${RS}${RC}${C_CHROME}${B_V}${RS}"); }

blank_row() { rnew; rpush; }

# ── bars (§2.2 ramp; §5.2 anatomy) ──────────────────────────────────────────
BARC=""
bar_build() { # value width frozen(0/1) [notch_at_value or ""]
  local v=$1 w=$2 frozen=$3 notch=${4:-}
  local fill=$(( (v * w + 50) / 100 )); (( fill > w )) && fill=$w
  local col; col=$(bar_color "$v"); [[ $frozen == 1 ]] && col=$C_ICE
  local np=-1
  [[ -n $notch ]] && np=$(( notch * w / 100 ))
  BARC=""
  local i
  for ((i=0; i<w; i++)); do
    if (( i < fill )); then BARC+="${col}${G_FILL}${RS}"
    elif (( i == np )); then BARC+="${C_CHROME}${G_NOTCH}${RS}"
    else BARC+="${C_TRACK}${G_EMPTY}${RS}"; fi
  done
}

statval() { # value frozen → colored right-aligned value, always 4 cells wide
  local v=$1 frozen=$2 col; col=$(bar_color "$v")
  if [[ $frozen == 1 ]]; then printf '%s' "${C_ICE}${G_FROZEN}$(printf '%3s' "$v")${RS}"
  else printf '%s' "${col}$(printf '%4s' "$v")${RS}"; fi
}

# ── title & footer bars ─────────────────────────────────────────────────────
push_title() { # left_text badges_plain badges_colored
  local left=$1 bp=$2 bc=$3
  local ll=${#left} bl=${#bp}
  local dashes=$(( IW - ll - bl - 4 )); (( dashes < 1 )) && dashes=1
  SCREEN+=("${C_CHROME}${B_TL}${B_H} ${RS}${left}${C_CHROME} $(repeat_str "$B_H" "$dashes")${RS}${bc}${C_CHROME}${B_H}${B_TR}${RS}")
}
push_footer() { # keys_plain keys_colored sync_plain sync_colored
  local kp=$1 kc=$2 sp=$3 sc=$4
  local dashes=$(( IW - ${#kp} - ${#sp} - 4 )); (( dashes < 1 )) && dashes=1
  SCREEN+=("${C_CHROME}${B_BL}${RS} ${kc} ${C_CHROME}$(repeat_str "$B_H" "$dashes")${RS}${sc}${C_CHROME}${B_H}${B_BR}${RS}")
}

key_chip() { # "f" "riends" → colored chip, appends to KP/KC
  KP+="[$1]$2 "
  KC+="${C_CHROME}[${RS}${C_BOLD}$1${RS}${C_CHROME}]${RS}$2 "
}

sync_cell() { # → SP (plain) SC (colored) — footer sync states (§5.9)
  local st age now; st=$(net_status); now=$(date +%s)
  age=$(( now - $(net_last_ok) ))
  if [[ -n ${FIXDIR:-} ]]; then SP=" fixtures "; SC="${C_CHROME} fixtures ${RS}"; return; fi
  if [[ -n ${FETCH_PID:-} ]] && kill -0 "$FETCH_PID" 2>/dev/null; then
    SP=" ${G_SPIN} "; SC=" ${C_MAILC}${G_SPIN}${RS} "; return
  fi
  case $st in
    ok) SP=" ${G_DOT_OK} $(age_str $age) "; SC=" ${C_GREEN}${G_DOT_OK}${RS}${C_CHROME} $(age_str $age) ${RS}" ;;
    retry) local rin; rin=$(net_retry_in); SP=" ${G_WAIT} retrying in ${rin}s "; SC=" ${C_AMBER}${G_WAIT} retrying in ${rin}s${RS} " ;;
    *) SP=" offline · data $(age_str $age) old "; SC=" ${C_CHROME}offline · data $(age_str $age) old ${RS}" ;;
  esac
}

# ── stage buffer ────────────────────────────────────────────────────────────
declare -a STG_SEGS   # per-row: "x<US>len<US>colored" joined by <RS-sep>
US=$'\x1f' RSEP=$'\x1e'
stage_reset() {
  STG_SEGS=()
  local i; for ((i=0; i<SH; i++)); do STG_SEGS[i]=""; done
}
stage_put() { # row x len colored — skips out-of-bounds
  local row=$1 x=$2 len=$3 str=$4
  (( row < 0 || row >= SH )) && return
  (( x < 0 )) && return
  (( x + len > IW )) && return
  STG_SEGS[row]+="${x}${US}${len}${US}${str}${RSEP}"
}
stage_emit() {
  local i seg segs x len str
  for ((i=0; i<SH; i++)); do
    rnew
    # order segments by x (few per row → simple selection)
    local -a xs=() ls=() ss=()
    local IFS=$RSEP
    for seg in ${STG_SEGS[i]}; do
      [[ -z $seg ]] && continue
      IFS=$US read -r x len str <<<"$seg"
      xs+=("$x"); ls+=("$len"); ss+=("$str")
    done
    unset IFS
    local n=${#xs[@]} j k
    while :; do
      local best=-1
      for ((j=0; j<n; j++)); do
        [[ -z ${xs[j]:-} ]] && continue
        if (( best == -1 || xs[j] < xs[best] )); then best=$j; fi
      done
      (( best == -1 )) && break
      x=${xs[best]}; len=${ls[best]}; str=${ss[best]}; unset "xs[best]"
      if (( x >= ${#RP} )); then
        rpad "$x"; RP+=$(repeat_str "?" "$len"); RC+=$str   # RP tracks width only
      fi
    done
    rpush
  done
}

# ── medal shelf (§5.2: max 2 rows, overflow +N, empty renders nothing) ──────
shelf_lines() { # medals_raw medals_ok → fills SHELF[] (colored) SHELF_W
  SHELF=() SHELF_W=0
  local ok=$2 raw=$1
  if [[ $ok != 1 ]]; then
    if [[ ${OPT_NOSCRAPE:-0} == 1 || -n $raw ]]; then return; fi
    SHELF=("${C_CHROME}${C_DIM}medals: unavailable${RS}"); SHELF_W=19
    return
  fi
  [[ -z $raw ]] && return
  local -a codes=()
  local m IFS=';'
  for m in $raw; do
    local name=${m%%|*} tier=${m##*|}
    codes+=("$(medal_code "$name")$(sup_tier "$tier")")
  done
  unset IFS
  # two rows of up to 2 codes each; overflow +N
  local inner=10
  local r1="" r2="" shown=0 total=${#codes[@]} c
  for c in "${codes[@]}"; do
    if (( ${#r1} + ${#c} + 1 <= inner )) && [[ $shown -lt 2 || -n $r1 && ${#r1} -lt 5 ]] && (( shown < 2 )); then
      r1+="${r1:+ }$c"; shown=$((shown+1))
    elif (( ${#r2} + ${#c} + 1 <= inner - 3 || shown >= total - 1 )) && (( shown < 4 )); then
      r2+="${r2:+ }$c"; shown=$((shown+1))
    else break; fi
  done
  local left=$(( total - shown ))
  (( left > 0 )) && r2+="${r2:+ }+$left"
  r1=$(trunc "$r1" $inner); r2=$(trunc "$r2" $inner)
  local tl="╭" tr="╮" bl="╰" br="╯" hh="─"
  [[ $TIER == A ]] && tl="+" tr="+" bl="+" br="+" hh="-"
  local pad1 pad2
  pad1=$(repeat_str " " $((inner - ${#r1}))); pad2=$(repeat_str " " $((inner - ${#r2})))
  SHELF=("${C_CHROME}${tl} medals $(repeat_str "$hh" $((inner - 6)))${tr}${RS}")
  SHELF+=("${C_CHROME}${B_V}${RS} ${C_MAILC}${r1}${RS}${pad1} ${C_CHROME}${B_V}${RS}")
  [[ -n $r2 ]] && SHELF+=("${C_CHROME}${B_V}${RS} ${C_MAILC}${r2}${RS}${pad2} ${C_CHROME}${B_V}${RS}")
  SHELF+=("${C_CHROME}${bl}$(repeat_str "$hh" $((inner+2)))${br}${RS}")
  SHELF_W=$((inner + 4))
}

# ── cobwebs: 90+ days quiet and the scene itself gathers dust ───────────────
# corner web + a spider hanging on its thread; derived from DAYS_QUIET, so a
# long-gone friend's stage is cobwebbed too. First push sweeps them away.
COBWEB_TL=(
  "┼──┼──┄"
  "┼ ╲"
  "┆  ╲"
  "     ●"
)
COBWEB_TL_A=(
  "+--+--."
  "+ \\"
  ":  \\"
  "     o"
)
cobwebbed() { # assoc_name → 0 if 90+ days quiet
  local -n CW=$1
  (( ${CW[DAYS_QUIET]:-0} >= 90 ))
}

# frozen-bar display state: solid ❄ while hibernating, and during the wake-up
# the last 4 ticks flicker frozen↔live — "stats fade from ❄ to live" (§5.3)
frozen_disp() { # assoc_name → echoes 0/1
  local -n FD=$1
  if [[ ${FD[HIB]:-0} == 1 ]]; then echo 1
  elif (( TICK < ${WAKE_UNTIL:--1} )); then
    local ph=$(( 16 - (WAKE_UNTIL - TICK) ))
    if (( ph < 12 )); then echo 1; else echo $(( TICK % 2 )); fi
  else echo 0; fi
}

# ── pet composition dispatcher (render ladder §9.2) ─────────────────────────
declare -a PET_LINES
PET_W=0 PET_H=0
pet_compose() { # assoc_name frame blink faint [flip]
  local -n P=$1
  local frame=$2 blink=$3 faint=$4 flip=${5:-0}
  if [[ -n $PIX_MODE && -n ${PIXF[${P[SPECIES]}/idle_1]:-} ]]; then
    PIX_BEARD_RGB=${P[BEARD_RGB]:-}
    pix_palette "${P[SPECIES]}" "${P[COLOR_HEX]}" "$faint"
    # elders wear spectacles — earned, like the beard (§6.7);
    # low energy adds bags under the eyes (the frazzle, §6.5)
    local specs=0; [[ ${P[STAGE]:-} == elder ]] && specs=1
    local tired=0; (( ${P[ENERGY]:-50} < 25 )) && tired=1
    # hunger wears the silhouette: starving pets go skinny, stuffed pets round out
    local body=0
    (( ${P[HUNGER]:-50} < 20 )) && body=-1
    (( ${P[HUNGER]:-50} >= 90 )) && body=1
    # the mouth follows the mood buckets: content/ecstatic smile, grumpy
    # and miserable frown, neutral keeps the straight face (§6.5)
    local moodf=0 mv=${P[MOOD]:-52}
    (( mv >= 72 )) && moodf=1
    (( mv <= 32 )) && moodf=-1
    # fitness ≥ 80 earns the six-pack (same bar as the idle stretches)
    local sixp=0; (( ${P[FITNESS]:-0} >= 80 )) && sixp=1
    # high energy dilates the eyes: big, black, too awake to blink
    local bigeye=0; (( ${P[ENERGY]:-50} >= 85 )) && bigeye=1
    # high curiosity scrunches the brows — the inspector face
    local brows=0; (( ${P[CURIOSITY]:-0} >= 75 )) && brows=1
    # high social wags the tail: appendages swish on the odd half-second beat
    local wag=0
    (( ${P[SOCIAL]:-0} >= 70 )) && wag=$(( ${TICK:-0} / 2 % 2 ))
    # wisdom grows the beard: stubble at 40, trimmed at 70, full sage at 90
    local beard=0 wv=${P[WISDOM]:-0}
    (( wv >= 40 )) && beard=1
    (( wv >= 70 )) && beard=2
    (( wv >= 90 )) && beard=3
    # critical health (< 15) rolls the sick pet in on a stretcher — with an
    # entrance: the empty gurney wheels in from the right (7 beats), parks
    # under the patient, and the pet hops aboard (3 beats). The pet stays
    # bedridden until health recovers, then the exit plays: leap off, land,
    # and the empty bed rolls back off the right edge. Session-local theater
    # keyed off the rising/falling edges, like the hatch flash; GURNEY_ID
    # pins the whole show to the pet that fell ill (friend renders share
    # these globals and must not inherit the dismount).
    local gurney=0 gid=${P[ID]:-self}
    if [[ $frame == sick* && -n ${P[HEALTH]:-} ]] && (( ${P[HEALTH]} < 15 )); then
      if [[ -z ${TICK:-} ]]; then
        gurney=1                       # snapshots skip straight to the pose
      else
        (( ${GURNEY_PREV:-0} == 0 )) && GURNEY_AT=$TICK
        local ge=$(( TICK - GURNEY_AT ))
        if   (( ge <= 6 )); then gurney="s$(( 28 - ge * 4 ))"
        elif (( ge == 7 )); then gurney=s0
        elif (( ge == 8 )); then gurney=j3
        elif (( ge == 9 )); then gurney=j8
        else gurney=1; fi
      fi
      GURNEY_PREV=1 GURNEY_ID=$gid GURNEY_OFF_AT=""
    elif [[ ${GURNEY_ID:-} == "$gid" && -n ${TICK:-} ]]; then
      if (( ${GURNEY_PREV:-0} == 1 )); then GURNEY_OFF_AT=$TICK; fi
      GURNEY_PREV=0
      if [[ -n ${GURNEY_OFF_AT:-} ]]; then
        local go=$(( TICK - GURNEY_OFF_AT ))
        if   (( go == 0 )); then gurney=j8   # the recovery leap
        elif (( go == 1 )); then gurney=j3
        elif (( go == 2 )); then gurney=j0   # back on solid ground
        elif (( go <= 9 )); then gurney="s$(( (go - 2) * 4 ))"
        else GURNEY_OFF_AT="" GURNEY_ID=""; fi
      fi
    else
      GURNEY_PREV=0
    fi
    # review duty (≥3 outbound reviews this week): the pet holds the spear
    local spearh=0; (( ${P[OUTBOUND7]:-0} >= 3 )) && spearh=1
    pix_render "${P[SPECIES]}" "$frame" "$blink" "$specs" "$tired" "$flip" "$body" "$moodf" "$sixp" "$bigeye" "$brows" "$wag" "$beard" "$gurney" "$spearh"
    PET_LINES=("${PIXOUT[@]}"); PET_W=$PIXOUT_W PET_H=$PIXOUT_H
  else
    # ASCII fallback tier: two-frame pixel names collapse to the §6 frames
    case $frame in
      sick_1|sick_2) frame=sick ;;
      celebrate_1|celebrate_2) frame=celebrate ;;
      hibernate_1|hibernate_2) frame=idle_1 ;;
    esac
    local face tint
    face=$(pick_face "${P[MOOD_BUCKET]:-neutral}" "${P[ENERGY]:-50}" \
      "$([[ $frame == sick ]] && echo 1 || echo 0)" \
      "$([[ $frame == sleep_1 || $frame == sleep_2 ]] && echo 1 || echo 0)" \
      "$([[ $frame == eat_2 ]] && echo 1 || echo 0)" \
      "$blink" "${P[WISDOM]:-0}")
    tint=$(fg "${P[COLOR256]:-180}")
    local elder=0; [[ ${P[STAGE]:-} == elder ]] && elder=1
    local sp=${P[SPECIES_ASCII]:-${P[SPECIES]}}
    [[ ${P[STAGE]:-} == hatchling ]] && frame=young
    compose_sprite "$sp" "$frame" "$face" "${P[PATTERN]:-solid}" \
      "${P[ACCESSORY]:-bare}" "$tint" "$elder" "$faint"
    PET_LINES=("${SPCOMP_COL[@]}")
    PET_H=${#PET_LINES[@]} PET_W=0
    local l i; for l in "${SPCOMP_PLAIN[@]}"; do (( ${#l} > PET_W )) && PET_W=${#l}; done
    # uniform width: pad every line so layout math holds on all rows
    for i in "${!PET_LINES[@]}"; do
      local short=$(( PET_W - ${#SPCOMP_PLAIN[i]} ))
      (( short > 0 )) && PET_LINES[i]+=$(repeat_str " " "$short")
    done
  fi
}

# ── voice line (§7): observe, never scold; always name the fact ─────────────
voice_pool() { # assoc_name self → fills VPOOL[] + VPOOL_URL[] (parallel)
  local -n P=$1
  local self=$2 n=${P[NAME]}
  VPOOL=() VPOOL_URL=()
  local login=${P[LOGIN]}
  local u_prof="https://github.com/$login"
  local u_merged="https://github.com/search?q=is%3Apr+author%3A$login+is%3Amerged&type=pullrequests"
  local u_stale="https://github.com/issues?q=user%3A$login+is%3Aopen+sort%3Aupdated-asc"
  local u_stars="https://github.com/$login?tab=stars"
  local u_prs="https://github.com/search?q=is%3Apr+author%3A$login&type=pullrequests"
  vline() { VPOOL+=("$1"); VPOOL_URL+=("${2:-}"); }   # every line links to its fact
  if [[ $self != 1 ]]; then
    if [[ ${P[HIB]} == 1 ]]; then
      if (( ${P[DAYS_QUIET]:-0} >= 90 )); then
        vline "$n has been gone ${P[DAYS_QUIET]} days. Mind the cobwebs." "$u_prof"
      fi
      vline "$n has been curled up for ${P[DAYS_QUIET]} days. Say hi when they're back." "$u_prof"
    elif (( ${P[OUTBOUND7]:-0} > 3 )); then
      vline "$n has been reviewing all week — someone's earning wisdom." "$u_prof"
    elif (( ${P[MERGES7]:-0} > 0 )); then
      vline "${P[MERGES7]} merges this week — $n eats well." "$u_merged"
    else
      vline "$n idles in the ${P[TOP_LANG]:-GitHub} sun." "$u_prof"
    fi
    return
  fi
  local d_dry=$(( ${P[MERGE_AGO_H]:-'-1'} >= 0 ? P[MERGE_AGO_H] / 24 : 8 ))
  if [[ ${P[HIB]} == 1 ]]; then
    if (( ${P[DAYS_QUIET]:-0} >= 90 )); then
      vline "${P[DAYS_QUIET]} days quiet. The cobwebs have cobwebs — the first push sweeps them away." "$u_prof"
      vline "A spider has moved in above $n. Neither is in a hurry." "$u_prof"
    else
      vline "${P[DAYS_QUIET]} days quiet. $n hibernates — stats frozen, no judgment. The first push wakes them." "$u_prof"
    fi
    return
  fi
  if (( ${P[MERGE_AGO_H]:-'-1'} >= 0 && P[MERGE_AGO_H] < 24 )); then
    vline "Merged #${P[MERGE_NUM]} $((P[MERGE_AGO_H] == 0 ? 1 : P[MERGE_AGO_H])) hours ago — $n is well fed." "${P[MERGE_URL]:-$u_merged}"
    (( ${P[MERGES7]} > 1 )) && vline "${P[MERGES7]} merges this week. The bowl runneth over." "$u_merged"
  fi
  if (( ${P[HUNGER]} < 20 )); then
    vline "$d_dry dry days. $n circles the empty bowl." "$u_merged"
    vline "The bowl echoes." "$u_merged"
  fi
  if (( ${P[ENERGY]} < 25 )); then
    local rx; rx=$(( ${P[RATIO_X100]:-100} / 100 ))
    vline "${rx}× your usual pace lately. $n naps pointedly." "$u_prof"
    vline "$n left a tiny note: 'take a walk'." "$u_prof"
  fi
  [[ ${P[SLEEPING]} == 1 ]] && vline "Quiet on the feed. $n sleeps while you do." "$u_prof"
  if (( ${P[CLEAN]} < 40 )); then
    vline "$(( ${P[STALE_ISSUES]} + ${P[STALE_PRS]} )) stale issues on ${P[DIRTY_REPO]:-your repos}. The flies have opinions." "$u_stale"
  fi
  (( ${P[SOCIAL]} < 30 )) && vline "$n watches the window. When did you last review a friend's PR?" "https://github.com/pulls/review-requested"
  if (( ${P[CURIOSITY]} >= 60 )); then
    if [[ -n ${P[NEW_LANG]} ]]; then vline "A new language this month! $n found a new toy." "$u_prof?tab=repositories"
    else vline "${P[STARS14]} stars given lately — $n bats the ball around." "$u_stars"; fi
  fi
  [[ ${P[MOOD_BUCKET]} == miserable ]] && vline "${P[CHANGESREQ7]} changes-requested this week. $n sulks in solidarity." "$u_prs"
  [[ ${P[DROWSY]} == 1 ]] && vline "${P[DAYS_QUIET]} quiet days. $n yawns — no rush." "$u_prof"
  if (( ${P[HAPPINESS]} > 80 )); then vline "All is well. $n hums a small tune." "$u_prof"; fi
  if (( ${#VPOOL[@]} == 0 )); then
    vline "A quiet moment on the feed. $n approves." "$u_prof"
    vline "$n idles in the ${P[TOP_LANG]:-GitHub} sun." "$u_prof"
  fi
}

# ── insight line (§5.2): the lowest stat's "why", hidden when all ≥ 50 ──────
insight_text() { # assoc_name self → INSIGHT ("" if quiet screen)
  local -n P=$1
  INSIGHT=""
  [[ ${P[HIB]} == 1 || ${P[STAGE]} == egg ]] && return
  local -a keys=(HUNGER ENERGY MOOD FITNESS CLEAN CURIOSITY SOCIAL WISDOM)
  local -a names=(hunger energy mood fitness cleanliness curiosity social wisdom)
  [[ -n ${P[HEALTH]} ]] && { keys+=(HEALTH); names+=(health); }
  local low=101 lowi=-1 i
  for i in "${!keys[@]}"; do
    local v=${P[${keys[i]}]:-100}
    (( v < low )) && { low=$v; lowi=$i; }
  done
  (( low >= 50 )) && return   # a happy screen is a quiet screen
  local why=""
  case ${names[lowi]} in
    hunger) why="no merged PRs are fresh — each merge feeds ${P[NAME]} for ~4 days" ;;
    energy) why="$(( ${P[RATIO_X100]:-100} / 100 ))× your usual pace, ${P[REST_GAPS]} rest gap(s) ≥ 6h in the last 24h" ;;
    mood) why="${P[CHANGESREQ7]} changes-requested vs ${P[APPROVED7]} approvals this week" ;;
    fitness) why="active ${P[ACTIVE21]} of the last 21 days — rhythm beats volume" ;;
    cleanliness) why="${P[STALE_ISSUES]} issues + ${P[STALE_PRS]} PRs idle >30d on ${P[DIRTY_REPO]:-recent repos}" ;;
    curiosity) why="no stars given or forks made in 14 days" ;;
    social) why="${P[OUTBOUND7]} comments on others' repos this week" ;;
    wisdom) why="wisdom climbs slowly — ${P[REVIEWS_TOTAL]} reviews given so far" ;;
    health) why="open security alerts — fixing them is the medicine" ;;
  esac
  if [[ -n ${P[CAPPED_BY]} ]]; then
    INSIGHT="happiness capped at 60 — ${P[CAPPED_BY]} ${P[CAPPED_VAL]} < 20 · $why"
  else
    INSIGHT="${names[lowi]} low — $why"
  fi
}

# ── ambient vignette selection (P3: one at a time, 5-pt hysteresis) ─────────
# preview knob: GITAGOTCHI_PRETEND_VIG=books|ball|flies|window|belly seeds the
# vignette; the knob also PINS it live — vignette_pick re-runs every 20
# ticks, and without the pin a seeded vignette the stats don't support is
# swept away on the first pass (the user watched books vanish instantly)
VIG_CUR=${GITAGOTCHI_PRETEND_VIG:-}
vignette_pick() { # assoc_name
  [[ -n ${GITAGOTCHI_PRETEND_VIG:-} ]] && { VIG_CUR=$GITAGOTCHI_PRETEND_VIG; return; }
  local -n P=$1
  local -a cand=()   # "value:name" for qualifying vignettes, lowest wins
  (( ${P[CLEAN]} < 40 )) && cand+=("${P[CLEAN]}:flies")
  (( ${P[SOCIAL]} < 30 )) && cand+=("${P[SOCIAL]}:window")
  (( ${P[FITNESS]} < 35 )) && cand+=("${P[FITNESS]}:belly")
  local pick="" best=101 c v n
  for c in "${cand[@]}"; do
    v=${c%%:*} n=${c##*:}
    (( v < best )) && { best=$v; pick=$n; }
  done
  # hysteresis: keep the current vignette unless its stat cleared threshold+5
  if [[ -n $VIG_CUR ]]; then
    local keep=0
    case $VIG_CUR in
      flies)  (( ${P[CLEAN]} < 45 )) && keep=1 ;;
      window) (( ${P[SOCIAL]} < 35 )) && keep=1 ;;
      belly)  (( ${P[FITNESS]} < 40 )) && keep=1 ;;
      # the ball yields upward: at 75 curiosity graduates to the book stack
      ball)   (( ${P[CURIOSITY]} >= 55 && ${P[CURIOSITY]} < 75 )) && keep=1 ;;
      books)  (( ${P[CURIOSITY]} >= 70 )) && keep=1 ;;
    esac
    (( keep )) && return
  fi
  if [[ -n $pick ]]; then VIG_CUR=$pick
  elif (( ${P[CURIOSITY]} >= 75 )); then VIG_CUR=books
  elif (( ${P[CURIOSITY]} >= 60 )); then VIG_CUR=ball
  else VIG_CUR=""; fi
}
