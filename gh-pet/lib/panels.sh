# gitagotchi — lib/panels.sh
# Expanded panel views (gitagotchi-panels.html): each dense panel opened into
# its full screen via its hotkey — vitals (s) · activity (g) · friends (f) ·
# feed (e). Same btop grammar as dense.sh: bordered boxes, identity border
# colors, hotkeys pinned in the frame, footer teaches the keys again.

# ══ vitals · expanded — the fix-it menu (mockup §vitals) ═════════════════════
# left: all 10 stats with meter · value · trend, the selected one opens a
# detail box (history, the human "why", the literal API source, ↵ → github).
# right: happiness composition — weight × value = points, misery cap stated
# where it's relevant instead of buried in docs.

VX_COMP_KEYS=(HUNGER MOOD ENERGY FITNESS CLEAN SOCIAL CURIOSITY WISDOM HEALTH)
VX_COMP_NAMES=(hunger mood energy fitness cleanliness social curiosity wisdom health)
VX_COMP_W=(20 20 15 10 10 10 5 5 5)

# facts in the why-line get bolded (mockup .why b): numbers with their units —
# "3 PRs merged", "#482", "4h", "feeds 14", "×1.0", "est. 2019", bare counts
VX_FACT_ERE='#[0-9]+|feeds [0-9]+|active [0-9]+|est\. [0-9]+|[+−]?[0-9]+ (PRs? merged|PRs?|approvals?|merges?|changes-requested|rest gap\(s\)|rest gaps?|stars given|stars|forks|comments/reviews|reviews given|reviews|languages|issues|days)|[+−]?[0-9]+\.[0-9]+|[+−]?[0-9]+[hd%]?'

vx_what() { # stat name → what this vital actually measures (the tooltip)
  case $1 in
    hunger)      printf 'how fed the pet is — merged PRs are meals, each digesting over ~2 days' ;;
    mood)        printf "the pet's temper — net feedback on your PRs: approvals lift it, changes-requested sting" ;;
    energy)      printf 'rest vs pace — quiet gaps ≥6h restore it, running hot above your own baseline drains it' ;;
    fitness)     printf 'consistency of activity — days active out of the last 21; rhythm, not volume' ;;
    cleanliness) printf 'repo hygiene — issues and PRs left idle over 30 days pile up as mess' ;;
    curiosity)   printf 'appetite for the new — repos explored, stars given, forks made, first tries of a language' ;;
    social)      printf "life outside your own repos — comments and reviews you give, friends you follow" ;;
    wisdom)      printf 'accumulated experience — reviews given, language breadth, years on GitHub; it only grows' ;;
    health)      printf 'security posture — open dependabot alerts make the pet sick' ;;
    happiness)   printf 'the weighted sum of everything above, with the misery cap as its floor' ;;
  esac
}

vx_suggest() { # stat name → one concrete way to raise it
  case $1 in
    hunger)      printf 'merge a PR — the bowl refills' ;;
    energy)      printf 'take a real break — gaps restore it' ;;
    mood)        printf 'ship something small' ;;
    fitness)     printf 'code a little most days' ;;
    cleanliness) printf 'close or triage a stale issue' ;;
    curiosity)   printf 'star a repo or fork something new' ;;
    social)      printf "comment on someone else's PR" ;;
    wisdom)      printf "review someone's code" ;;
    health)      printf 'fix the dependabot alerts' ;;
  esac
}

vx_trend() { # hist_str value → VXT_P VXT_C (delta over the derived history)
  VXT_P=" ·" VXT_C="$(fgt "$RGB_FAINT") ·${RS}"
  local h=$1
  [[ -z $h || -z $2 ]] && return
  local first=${h%% *}
  local d=$(( $2 - first ))
  if (( d > 0 )); then VXT_P="+$d"; VXT_C="$(fgt "$RGB_GREEN")+$d${RS}"
  elif (( d < 0 )); then VXT_P="−${d#-}"; VXT_C="$(fgt "$RGB_RED")−${d#-}${RS}"
  else VXT_P=" 0"; VXT_C="$(fgt "$RGB_FAINT") 0${RS}"; fi
}

vx_wrapn() { # text maxw maxlines → VXW[] (word wrap, last line truncated)
  local t=$1 maxw=$2 maxn=$3
  VXW=()
  while [[ -n $t ]] && (( ${#VXW[@]} < maxn )); do
    if (( ${#t} <= maxw )); then VXW+=("$t"); break; fi
    if (( ${#VXW[@]} == maxn - 1 )); then VXW+=("$(trunc "$t" "$maxw")"); break; fi
    local cut=${t:0:maxw+1}
    local line=${cut% *}
    (( ${#line} > maxw )) && line=${t:0:maxw}
    VXW+=("$line")
    t=${t:${#line}}
    t=${t# }
  done
}

vx_hl() { # line ere [on off] → VXHL: ere matches wrapped in on…off, width
  local s=$1 ere=$2       # unchanged. Defaults bold/unbold (SGR 22 clears bold
  local on=${3:-$'\e[1m'} # only, so the run color survives); pass a color+bold
  local off=${4:-$'\e[22m'}   # pair to render highlights lighter than the body
  VXHL=""
  while [[ -n $s && $s =~ $ere ]]; do
    local m=${BASH_REMATCH[0]}
    local pre=${s%%"$m"*}
    VXHL+="${pre}${on}${m}${off}"
    s=${s#*"$m"}
  done
  VXHL+=$s
}

vx_sel_sync() { # VSEL (one cursor over both panels) → SEL_STAT / CSEL
  if (( VSEL < 10 )); then SEL_STAT=$VSEL CSEL=-1
  else CSEL=$((VSEL - 10)); fi
}
vx_jump_right() { # → the comp row for the stat under the left cursor
  local ci
  VSEL=10
  for ci in "${!VX_COMP_NAMES[@]}"; do
    [[ ${VX_COMP_NAMES[ci]} == "${STAT_NAMES[SEL_STAT]}" ]] && { VSEL=$((10 + ci)); break; }
  done
}
vx_jump_left() { # → the list row for the stat under the right cursor
  local si
  VSEL=$SEL_STAT
  for si in "${!STAT_NAMES[@]}"; do
    [[ ${STAT_NAMES[si]} == "${VX_COMP_NAMES[CSEL]}" ]] && { VSEL=$si; break; }
  done
}

vx_stat_url() { # assoc_name stat_name → VXURL (the stat's fix-it page, §5.4)
  VXURL=""            # note: clobbers D_WHY/D_SRC/D_URL — call before they matter
  local si
  for si in "${!STAT_NAMES[@]}"; do
    if [[ ${STAT_NAMES[si]} == "$2" ]]; then
      stat_detail_info "$1" "$si"
      VXURL=$D_URL
      return
    fi
  done
}

vx_hist_rows() { # "v1 v2 …" avail_w rows → VXH[0..rows-1], VXH_W, VXH_N
  # one column per refresh with a breathing gap between bars; when the box is
  # narrower than the history, the most recent refreshes win
  local -a vals=($1)
  local avail=$2 rows=${3:-3}
  local n=${#vals[@]}
  local maxn=$(( (avail + 1) / 2 )); (( maxn < 1 )) && maxn=1
  (( n > maxn )) && vals=("${vals[@]:$((n - maxn))}")
  VXH_N=${#vals[@]}
  VXH_W=$(( VXH_N * 2 - 1 ))
  VXH=()
  # bars scale to the window's own range — a 3-point wiggle over five hours
  # should read as a slope, not thirty identical columns
  local v
  VXH_MIN=101 VXH_MAX=-1
  for v in "${vals[@]}"; do
    (( v < VXH_MIN )) && VXH_MIN=$v
    (( v > VXH_MAX )) && VXH_MAX=$v
  done
  local span=$(( VXH_MAX - VXH_MIN ))
  local r BL FN
  BL=$(fgt "$RGB_BLUE"); FN=$(fgt "$RGB_FAINT")
  for ((r=0; r<rows; r++)); do
    local out="" k=0
    for v in "${vals[@]}"; do
      local h8
      if (( span > 0 )); then
        h8=$(( 6 + (v - VXH_MIN) * (rows * 8 - 6) / span ))
      else
        h8=$(( rows * 4 ))          # a truly flat series sits mid-height
      fi
      local base=$(( (rows - 1 - r) * 8 ))
      local f=$(( h8 - base ))
      (( f < 0 )) && f=0; (( f > 8 )) && f=8
      if (( f > 0 )); then out+="${BL}${EIGHTHS:f:1}${RS}"
      else out+="${FN}${C_DIM}▁${RS}"; fi
      k=$((k + 1))
      (( k < VXH_N )) && out+=" "
    done
    VXH+=("$out")
  done
}

draw_vitals_x() { # assoc_name self — 1:1 with the mockup's vitals screen
  local -n P=$1
  local self=$2
  scr_reset
  local MU FA IN
  MU=$(fgt "$RGB_MUTED"); FA=$(fgt "$RGB_FAINT"); IN=$(fgt "$RGB_INK")
  local frozen; frozen=$(frozen_disp "$1")
  local ph=$((LINES - 1))
  # the composition panel is part of the design (mockup grid 1.25fr/1fr) —
  # both columns shrink before the right one disappears
  local two=0 lw=$COLS
  (( COLS >= 72 )) && { two=1; lw=$(( COLS * 5 / 9 )); }
  VX_TWO=$two
  local vkey="jk/tab select · ↵ open"
  (( lw < 48 )) && vkey="jk · ↵"
  panel_frame 0 0 "$lw" "$ph" "$RGB_GREEN" "vitals · all 10" "$vkey"

  # ── the list: label · meter · value · trend (mockup .vlist) ──
  local vx=3 viw=$((lw - 6))
  local cells=$(( viw - 2 - 12 - 1 - 3 - 1 - 2 ))
  (( cells > 16 )) && cells=16      # mockup meters: 16 cells
  (( cells < 6 )) && cells=6
  # row pitch: the bars always breathe like the mockup; only terminals too
  # short to keep a usable detail card underneath fall back to compact
  local vpitch=1
  (( ph >= 31 )) && vpitch=2
  local vr=1 i
  for i in "${!STAT_KEYS[@]}"; do
    local key=${STAT_KEYS[i]} nm=${STAT_NAMES[i]}
    local v=${P[$key]:-}
    if (( i == 9 )); then     # happiness sits under a dashed separator
      scr_put "$vr" "$vx" "$viw" "$(fgt "$RGB_SEP")$(repeat_str "╌" "$viw")${RS}"
      vr=$((vr + 1))
    fi
    local selp="  " labc=$MU row rlen
    if (( i == SEL_STAT )); then
      selp="${G_SEL} "; labc="${IN}${C_BOLD}"
      (( CSEL >= 0 )) && selp="${FA}${G_SEL} ${RS}"   # cursor is on the right
    fi
    (( i == 9 )) && labc="${IN}${C_BOLD}"
    row="$(fgt "$RGB_GREEN")${selp}${RS}"
    # every label is a hyperlink to the page that raises the stat (§5.4)
    local VXURL; vx_stat_url "$1" "$nm"
    if [[ $nm == health ]]; then      # mockup: health 🔒 self — the lock tag
      row+="$(osc8 "$VXURL" "${labc}health${RS} ${FA}self${RS}") "   # 6+1+4+1 = 12
    else
      row+="$(osc8 "$VXURL" "${labc}$(printf '%-12s' "$nm")${RS}")"
    fi
    if [[ $nm == health && -z $v ]]; then
      row+="${FA}─ private · by design${RS}"
      rlen=$(( 2 + 12 + 21 ))
    else
      dmeter "${v:-0}" "$cells" "$frozen"
      vx_trend "${P[HIST_${key}]:-}" "$v"
      row+="$DM $(dval "${v:-0}" "$frozen") ${VXT_C}"
      rlen=$(( 2 + 12 + cells + 1 + 3 + frozen + 1 + ${#VXT_P} ))
    fi
    if (( i == SEL_STAT && CSEL < 0 )); then   # tint follows the cursor
      local selbg=$'\e[48;2;16;34;22m'
      local pad=$(( viw - rlen )); (( pad < 0 )) && pad=0
      row="${selbg}${row//$'\e[0m'/$'\e[0m'${selbg}}$(repeat_str " " "$pad")"$'\e[49m'
      rlen=$viw
    fi
    scr_put "$vr" "$vx" "$rlen" "$row"
    vr=$((vr + vpitch))
  done
  (( vpitch == 2 )) && vr=$((vr - 1))   # no trailing gap after the last row

  # ── detail box (mockup .detail): h3 · meter · history · why · src · link ──
  local dtop=$((vr + 1))
  local dh=$(( ph - 1 - dtop ))
  (( dh > 18 )) && dh=18
  if (( dh >= 5 )); then
    local dnm=${STAT_NAMES[SEL_STAT]} dv=${P[${STAT_KEYS[SEL_STAT]}]:-}
    stat_detail_info "$1" "$SEL_STAT"
    panel_frame "$dtop" 2 $((lw - 4)) "$dh" "40;110;55" "" ""
    local dx=4 diw=$((lw - 8)) dr=$((dtop + 1))
    local dend=$((dtop + dh - 1))
    if [[ $dnm == health && -z $dv ]]; then
      scr_put "$dr" "$dx" 30 "${IN}${C_BOLD}health${RS}  ${FA}─ private · by design${RS}"
      dr=$((dr + 1))
    else
      # h3: name · big value · delta (mockup: hunger 71 ▲ +7 today)
      vx_trend "${P[HIST_${STAT_KEYS[SEL_STAT]}]:-}" "$dv"
      local dtxt dcol
      case ${VXT_P:0:1} in
        +) dtxt="▲ ${VXT_P} today"; dcol=$RGB_GREEN ;;
        −) dtxt="▼ ${VXT_P} today"; dcol=$RGB_RED ;;
        *) dtxt="· steady";         dcol=$RGB_FAINT ;;
      esac
      local vrgb=$RGB_GREEN
      (( ${dv:-0} < 50 )) && vrgb=$RGB_YELLOW
      (( ${dv:-0} < 20 )) && vrgb=$RGB_RED
      scr_put "$dr" "$dx" $(( ${#dnm} + 1 + ${#dv} + 2 + ${#dtxt} )) \
        "${IN}${C_BOLD}${dnm}${RS} $(fgt "$vrgb")${C_BOLD}${dv}${RS}  $(fgt "$dcol")${dtxt}${RS}"
      dr=$((dr + 1))
      # big meter, 24 cells (mockup .meter.big)
      local bigc=24; (( bigc > diw )) && bigc=$diw
      dmeter "${dv:-0}" "$bigc" "$frozen"
      scr_put "$dr" "$dx" "$bigc" "$DM"
      dr=$((dr + 1))
    fi

    # ── budget the rest of the card: breathing blanks and history rows
    # compress before any fact is dropped ──
    local hist=${P[HIST_${STAT_KEYS[SEL_STAT]}]:-}
    [[ $dnm == health && -z $dv ]] && hist=""
    local VXW VXHL wl
    vx_wrapn "$D_WHY" "$diw" 3
    local wl_n=${#VXW[@]}
    local sq=$D_SRC srest=""
    if [[ $D_SRC == *" · "* ]]; then sq=${D_SRC%% · *}; srest="· ${D_SRC#* · }"; fi
    sq=$(trunc "$sq" $((diw - 5)))
    local src_n=0
    [[ -n $D_SRC ]] && src_n=1
    if (( src_n )) && [[ -n $srest ]] && (( 5 + ${#sq} + 1 + ${#srest} > diw )); then src_n=2; fi
    local link_n=0; [[ -n $D_URL ]] && link_n=1
    local hr_n=0; [[ -n $hist ]] && hr_n=3
    local b1=1 b2=1 b3=1
    local remaining=$(( dend - dr ))
    local need=$(( b1 + (hr_n ? hr_n + 2 : 0) + b2 + wl_n + src_n + b3 + link_n ))
    while (( need > remaining )); do
      if   (( b3 ));        then b3=0
      elif (( src_n > 1 )); then src_n=1
      elif (( hr_n == 3 )); then hr_n=2   # bars shrink before the gap goes
      elif (( b1 ));        then b1=0
      elif (( b2 ));        then b2=0
      elif (( wl_n > 2 ));  then wl_n=2
      elif (( hr_n ));      then hr_n=0
      elif (( wl_n > 1 ));  then wl_n=1
      elif (( link_n ));    then link_n=0
      elif (( src_n ));     then src_n=0
      else break; fi
      need=$(( b1 + (hr_n ? hr_n + 2 : 0) + b2 + wl_n + src_n + b3 + link_n ))
    done

    (( b1 )) && dr=$((dr + 1))
    if (( hr_n )); then
      # history: gapped blue columns, the most recent hours that fit
      local VXH VXH_W VXH_N
      vx_hist_rows "$hist" "$diw" "$hr_n"
      local hr
      for ((hr=0; hr<hr_n; hr++)); do
        scr_put "$dr" "$dx" "$VXH_W" "${VXH[hr]}"
        dr=$((dr + 1))
      done
      dr=$((dr + 1))   # breathing room between the bars and their caption
      local hcap="last ${VXH_N} hours · derived hourly"
      if (( VXH_MAX > VXH_MIN )); then hcap+=" · ${VXH_MIN}–${VXH_MAX}"
      else hcap+=" · steady at ${VXH_MIN}"; fi
      hcap=$(trunc "$hcap" "$diw")
      scr_put "$dr" "$dx" ${#hcap} "${FA}${hcap}${RS}"
      dr=$((dr + 1))
    fi
    (( b2 )) && dr=$((dr + 1))
    # the human why (facts bolded), its literal source, the door to github;
    # a budget-trimmed why re-wraps so its last line ends in an ellipsis
    (( wl_n < ${#VXW[@]} )) && vx_wrapn "$D_WHY" "$diw" "$wl_n"
    for wl in "${VXW[@]:0:wl_n}"; do
      vx_hl "$wl" "$VX_FACT_ERE" "${IN}${C_BOLD}" $'\e[22m'"$(fgt "$RGB_VOICE")"
      # "#482" links straight to the PR itself (same convention as the feed)
      if [[ -n ${P[MERGE_URL]:-} && $wl =~ \#[0-9]+ ]]; then
        local prm=${BASH_REMATCH[0]}
        VXHL=${VXHL/"$prm"/$(osc8 "${P[MERGE_URL]}" "$prm")}
      fi
      scr_put "$dr" "$dx" ${#wl} "$(fgt "$RGB_VOICE")${VXHL}${RS}"
      dr=$((dr + 1))
    done
    if (( src_n )); then
      # src: the query in cyan links to the very search it names; the
      # tier/cadence tail wraps to its own line when it doesn't fit
      local sqc; sqc=$(osc8 "$D_URL" "$(fgt "$RGB_CYAN")${C_DIM}${sq}${RS}")
      if (( src_n == 2 )); then
        scr_put "$dr" "$dx" $(( 5 + ${#sq} )) "${FA}src: ${RS}${sqc}"
        dr=$((dr + 1))
        srest=$(trunc "$srest" $((diw - 5)))
        scr_put "$dr" $((dx + 5)) ${#srest} "${FA}${srest}${RS}"
      else
        local slen=$(( 5 + ${#sq} )) stail=$srest
        (( 5 + ${#sq} + 1 + ${#stail} > diw )) && stail=""
        [[ -n $stail ]] && slen=$(( slen + 1 + ${#stail} ))
        scr_put "$dr" "$dx" "$slen" "${FA}src: ${RS}${sqc}${stail:+ ${FA}${stail}${RS}}"
      fi
      dr=$((dr + 1))
    fi
    (( b3 )) && dr=$((dr + 1))
    if (( link_n )); then
      # the open-link button (mockup .openlink); shorter label when cramped
      local lnk="↵ ${D_OPEN:-open} on github ↗"
      (( ${#lnk} + 4 > diw )) && lnk="↵ open on github ↗"
      scr_put "$dr" "$dx" $(( ${#lnk} + 4 )) \
        "$(osc8 "$D_URL" "$(fgt "70;110;160")[ ${RS}$(fgt "$RGB_BLUE")${lnk}${RS}$(fgt "70;110;160") ]${RS}")"
    fi
  fi

  # ── right panel: happiness · how it's built (mockup .comp) ──
  if (( two )); then
    local rx=$((lw + 1)) rw2=$((COLS - lw - 1))
    local ctitle="happiness · how it's built"
    (( rw2 < 35 )) && ctitle="how it's built"
    panel_frame 0 "$rx" "$rw2" "$ph" "126;226;168" "$ctitle" "jk/tab"
    local cx=$((rx + 2)) ciw=$((rw2 - 4)) cr=1
    # the formula caption always reads in full — wrap instead of truncating
    local VXW cl
    vx_wrapn "weight × current value = points toward 100" "$ciw" 2
    for cl in "${VXW[@]}"; do
      scr_put "$cr" "$cx" ${#cl} "${MU}${cl}${RS}"
      cr=$((cr + 1))
    done
    cr=$((cr + 1))
    # row pitch: breathe like the mockup when the terminal is tall enough
    local pitch=1
    (( ph >= 31 )) && pitch=2
    local barw=$(( ciw - 12 - 3 - 1 - 1 - 4 )); (( barw < 6 )) && barw=6
    local ci
    for ci in "${!VX_COMP_KEYS[@]}"; do
      (( cr >= ph - 8 )) && break
      local cnm=${VX_COMP_NAMES[ci]} cwt=${VX_COMP_W[ci]}
      local cv=${P[${VX_COMP_KEYS[ci]}]:-}
      local VXURL; vx_stat_url "$1" "$cnm"    # the points link to their fix
      local cnmc=$MU
      (( ci == CSEL )) && cnmc="${IN}${C_BOLD}"
      local crow="$(osc8 "$VXURL" "${cnmc}$(printf '%-12s' "$cnm")${RS}")${FA}$(printf '%2s' "$cwt")%${RS} "
      if [[ -z $cv ]]; then
        crow+="${FA}─ private (weights renormalize)${RS}"
        local pvis=$(( 12 + 4 + 31 )); (( pvis > ciw )) && pvis=$ciw
        scr_put "$cr" "$cx" "$pvis" "$crow"
      else
        local p10=$(( cwt * cv / 10 ))            # points ×10
        local fill=$(( p10 * barw / 200 )); (( fill > barw )) && fill=$barw
        local crgb=$RGB_GREEN
        (( cv < 50 )) && crgb=$RGB_YELLOW
        (( cv < 20 )) && crgb=$RGB_RED
        crow+="$(fgt "$crgb")$(repeat_str "█" "$fill")$(fgt "$RGB_TRACK")$(repeat_str "█" $((barw - fill)))${RS}"
        crow+=" ${IN}${C_BOLD}$(printf '%4s' "$((p10 / 10)).$((p10 % 10))")${RS}"
        local cvis=$(( 12 + 4 + barw + 5 ))
        if (( ci == CSEL )); then     # inspected row: same tint as the list
          local selbg=$'\e[48;2;16;34;22m'
          local cpad=$(( ciw - cvis )); (( cpad < 0 )) && cpad=0
          crow="${selbg}${crow//$'\e[0m'/$'\e[0m'${selbg}}$(repeat_str " " "$cpad")"$'\e[49m'
          cvis=$ciw
        fi
        scr_put "$cr" "$cx" "$cvis" "$crow"
      fi
      # the tooltip rides the gap right under the inspected row: what this
      # vital IS — the detail card already tells you what you did
      if (( ci == CSEL && pitch == 2 && cr + 1 < ph - 1 )); then
        local itxt="${G_SEL} $(marquee "$(vx_what "$cnm")" $((ciw - 2)))"
        scr_put $((cr + 1)) "$cx" ${#itxt} "$(osc8 "$VXURL" "${MU}${itxt}${RS}")"
      fi
      cr=$((cr + pitch))
    done
    (( pitch == 2 )) && cr=$((cr - 1))
    scr_put "$cr" "$cx" "$ciw" "$(fgt "$RGB_SEP")$(repeat_str "╌" "$ciw")${RS}"
    cr=$((cr + 1))
    # total row: happiness bold left, the value pinned to the points column
    local totv=${P[HAPPINESS]:-0}
    scr_put "$cr" "$cx" 9 "${IN}${C_BOLD}happiness${RS}"
    if [[ -n ${P[CAPPED_BY]:-} ]]; then
      local rawn="(raw ${P[HAPPY_RAW]}, capped)"
      scr_put "$cr" $((cx + 10)) ${#rawn} "${FA}${rawn}${RS}"
    fi
    scr_put "$cr" $((cx + ciw - ${#totv})) ${#totv} "$(fgt "$RGB_GREEN")${C_BOLD}${totv}${RS}"
    cr=$((cr + 2))
    # Tab inspector, compact layout: no gap rows, so the derivation line
    # takes the slot above the capnote instead
    if (( pitch == 1 && CSEL >= 0 && CSEL < ${#VX_COMP_NAMES[@]} && cr - 1 < ph - 1 )); then
      local inm=${VX_COMP_NAMES[CSEL]}
      local VXURL; vx_stat_url "$1" "$inm"
      local itxt="${inm} — $(vx_what "$inm")"
      itxt="${G_SEL} $(marquee "$itxt" $((ciw - 2)))"
      scr_put $((cr - 1)) "$cx" ${#itxt} "$(osc8 "$VXURL" "${MU}${itxt}${RS}")"
    fi
    # capnote (mockup .capnote): amber box, the rule stated where it matters
    if (( cr + 6 <= ph )); then
      panel_frame "$cr" $((rx + 1)) $((rw2 - 2)) 6 "150;115;35" "" ""
      local ntext hlpat capstat=""
      if [[ -n ${P[CAPPED_BY]:-} ]]; then
        ntext="⚠ misery cap: happiness capped at 60 — ${P[CAPPED_BY]} is ${P[CAPPED_VAL]}, below 20. Fastest fix: $(vx_suggest "${P[CAPPED_BY]}")."
        hlpat="misery cap:|${P[CAPPED_BY]} is ${P[CAPPED_VAL]}"
        capstat="${P[CAPPED_BY]} is ${P[CAPPED_VAL]}"
      else
        local mn="" mv=101 si
        for si in "${!VX_COMP_KEYS[@]}"; do
          local sv=${P[${VX_COMP_KEYS[si]}]:-}
          [[ -z $sv ]] && continue
          (( sv < mv )) && { mv=$sv; mn=${VX_COMP_NAMES[si]}; }
        done
        ntext="⚠ misery cap: if any stat falls below 20, happiness caps at 60 — starving can't be averaged away."
        hlpat="misery cap:"
        if [[ -n $mn ]]; then
          ntext+=" Closest to the line right now: ${mn} ${mv} ($(vx_suggest "$mn"))."
          hlpat+="|${mn} ${mv}"
          capstat="${mn} ${mv}"
        fi
      fi
      # the named stat links to its own fix-it page
      local VXURL=""
      [[ -n $capstat ]] && vx_stat_url "$1" "${capstat%% *}"
      local VXW VXHL nl
      local nr=$((cr + 1))
      vx_wrapn "$ntext" $((rw2 - 6)) 4
      for nl in "${VXW[@]}"; do
        vx_hl "$nl" "$hlpat"
        if [[ -n $VXURL && $nl == *"$capstat"* ]]; then
          VXHL=${VXHL/"$capstat"/$(osc8 "$VXURL" "$capstat")}
        fi
        scr_put "$nr" $((rx + 3)) ${#nl} "$(fgt "$RGB_YELLOW")${VXHL}${RS}"
        nr=$((nr + 1))
      done
    fi
  fi

  dense_footer $((LINES - 1)) "jk/tab move" "←→ switch panel" "↵ open on github" "esc back"
  scr_emit
}

# ══ activity · expanded — graph view (mockup §activity) ══════════════════════
# answers "am I in a healthy rhythm?", not "am I productive?": range tabs, the
# big graph with baseline + annotations, weekday rhythm, 12-week calendar.

act_cycle_range() { # assoc_name dir(1|-1)
  local -n A=$1
  local has_y=0; [[ -n ${A[EVWEEKS]:-} ]] && has_y=1
  if [[ $2 == -1 ]]; then
    case $ACT_RANGE in
      14) if (( has_y )); then ACT_RANGE=365; else ACT_RANGE=60; fi ;;
      60) ACT_RANGE=14 ;;
      *)  ACT_RANGE=60 ;;
    esac
  else
    case $ACT_RANGE in
      14) ACT_RANGE=60 ;;
      60) if (( has_y )); then ACT_RANGE=365; else ACT_RANGE=14; fi ;;
      *)  ACT_RANGE=14 ;;
    esac
  fi
}

act_shade() { # value peak → rgb (4-step contribution ramp)
  local v=$1 peak=$2
  (( peak < 1 )) && peak=1
  if (( v == 0 )); then printf '%s' "$ACT_G0"; return; fi
  local t=$(( v * 100 / peak ))
  if (( t < 31 )); then printf '%s' "$ACT_G1"
  elif (( t < 56 )); then printf '%s' "$ACT_G2"
  elif (( t < 81 )); then printf '%s' "$ACT_G3"
  else printf '%s' "$ACT_G4"; fi
}

draw_activity_x() { # assoc_name self — 1:1 with the mockup's graph view
  local -n P=$1
  scr_reset
  local MU FA IN
  MU=$(fgt "$RGB_MUTED"); FA=$(fgt "$RGB_FAINT"); IN=$(fgt "$RGB_INK")
  local ph=$((LINES - 1))
  local unit=d; (( ACT_RANGE == 365 )) && unit=w
  panel_frame 0 0 "$COLS" "$ph" "$RGB_ACT" \
    "activity · ${P[ACT_SRC]:-events}/day" "tab range · esc back"

  # ── range tabs (mockup .tabs: the active one bright + bold, no glyph) ──
  local -a ranges=(14 60) rlabels=("14d" "60d")
  [[ -n ${P[EVWEEKS]:-} ]] && { ranges+=(365); rlabels+=("1y"); }
  local tx=2 ti
  for ti in "${!ranges[@]}"; do
    local lb=" ${rlabels[ti]} "
    if (( ranges[ti] == ACT_RANGE )); then
      scr_put 1 "$tx" $(( ${#lb} + 2 )) "$(fgt "$RGB_ACT")[${RS}${IN}${C_BOLD}${lb}${RS}$(fgt "$RGB_ACT")]${RS}"
    else
      scr_put 1 "$tx" $(( ${#lb} + 2 )) "${FA}[${RS}${MU}${lb}${RS}${FA}]${RS}"
    fi
    tx=$(( tx + ${#lb} + 3 ))
  done

  # ── row budget: tabs · marks · graph · marks · axis · meta · subgrid ──
  local sub_h=9      # 7 calendar rows + borders — the grid fills the card
  local g_rows=$(( ph - 8 - sub_h ))   # −8: a blank row above the subgrid
  if (( g_rows < 4 )); then
    sub_h=0
    g_rows=$(( ph - 8 ))
    (( g_rows < 3 )) && g_rows=3
  fi
  (( g_rows > 12 )) && g_rows=12   # stubby, like the mockup — not a skyline

  # ── graph data per range (annotations live on their own marks rows) ──
  local gdata gpeak=0 gbase nd v
  if (( ACT_RANGE == 365 )); then
    gdata=${P[EVWEEKS]}
    local -a warr=($gdata)
    nd=${#warr[@]}
    (( nd > (COLS - 4) / 2 )) && nd=$(( (COLS - 4) / 2 ))
    for v in "${warr[@]:$(( ${#warr[@]} - nd ))}"; do (( v > gpeak )) && gpeak=$v; done
    gbase=$(( ${P[BASE_PD_X100]:-100} * 7 ))
  else
    gdata=${P[EVDAYS]:-0}
    local -a darr=($gdata)
    local dn=${#darr[@]}
    nd=$ACT_RANGE
    (( nd > dn )) && nd=$dn
    (( nd > (COLS - 4) / 2 )) && nd=$(( (COLS - 4) / 2 ))
    for v in "${darr[@]:$((dn - nd))}"; do (( v > gpeak )) && gpeak=$v; done
    gbase=${P[BASE_PD_X100]:-100}
  fi
  build_graph "$gdata" "$gpeak" "$gbase" "$nd" "$g_rows" "" "" -1 "" ""
  local gx=2 gtop=3 r
  for ((r=0; r<g_rows; r++)); do
    scr_put $((gtop + r)) "$gx" $((nd * 2)) "${DGRAPH_LINES[r]}"
  done
  # baseline label at the graph's right edge (mockup .baseline .bl)
  local bl_lbl
  if (( ACT_RANGE == 365 )); then
    bl_lbl="┈ 90d baseline · $(( gbase / 100 )).$(( (gbase % 100) / 10 ))/wk"
  else
    bl_lbl="┈ 90d baseline · $(( gbase / 100 )).$(( (gbase % 100) / 10 ))"
  fi
  if (( gx + nd * 2 + ${#bl_lbl} + 2 < COLS - 2 )); then
    scr_put $((gtop + DGRAPH_BASEROW)) $((gx + nd * 2 + 1)) ${#bl_lbl} "$(fgt "$RGB_ORANGE")${C_DIM}${bl_lbl}${RS}"
  fi

  # ── marks: every merge ▲ above the graph (newest carries its number);
  # the rest gap and the latest weekend celebrated below (mockup .marks) ──
  local mt=2 mb=$((gtop + g_rows)) off=$(( 60 - nd ))
  if (( ACT_RANGE != 365 )); then
    local -a midxs=(${P[MERGE_IDXS]:-})
    local newest=${P[MERGE_IDX]:--1} mi
    # the newest merge's label claims its slot first; plain ticks that would
    # collide are skipped by the compositor
    if (( newest >= 0 )) && [[ -n ${P[MERGE_NUM]:-} ]]; then
      local ncol=$(( (newest - off) * 2 ))
      if (( ncol >= 0 && ncol < nd * 2 )); then
        local mlbl="▲ #${P[MERGE_NUM]}"
        local mx=$(( gx + ncol ))
        (( mx + ${#mlbl} > gx + nd * 2 )) && mx=$(( gx + nd * 2 - ${#mlbl} ))
        scr_put "$mt" "$mx" ${#mlbl} "$(osc8 "${P[MERGE_URL]:-}" "$(fgt "$RGB_ORANGE")${mlbl}${RS}")"
      fi
    fi
    for mi in "${midxs[@]}"; do
      (( mi == newest )) && continue
      local mcol=$(( (mi - off) * 2 ))
      (( mcol < 0 || mcol >= nd * 2 )) && continue
      scr_put "$mt" $(( gx + mcol )) 1 "$(fgt "$RGB_ORANGE")▲${RS}"
    done
    # rest gap — ice-blue, celebrated, not shamed
    local gg_c0=-1 gg_c1=-1
    if [[ -n ${P[GAP_IDX]:-} ]]; then
      local glbl="└ rest gap · ${P[GAP_DAYS]}d ┘"
      local gcol=$(( (${P[GAP_IDX]} - off) * 2 ))
      if (( gcol >= 0 && gcol < nd * 2 )); then
        local gx2=$(( gx + gcol - ${#glbl} / 2 ))
        (( gx2 < gx )) && gx2=$gx
        (( gx2 + ${#glbl} > gx + nd * 2 )) && gx2=$(( gx + nd * 2 - ${#glbl} ))
        scr_put "$mb" "$gx2" ${#glbl} "$(fgt "$RGB_ICE")${glbl}${RS}"
        gg_c0=$gx2; gg_c1=$(( gx2 + ${#glbl} ))
      fi
    fi
    # the latest full weekend in the window — a quiet weekend is a feature
    local dow; printf -v dow '%(%u)T' -1
    local sat=$(( 59 - ( (dow - 6 + 7) % 7 ) ))
    (( sat + 1 > 59 )) && sat=$(( sat - 7 ))
    local wlbl="└ weekend ┘" wtry
    for wtry in 0 1; do
      local wcol=$(( (sat - off) * 2 ))
      if (( wcol >= 0 && wcol + 4 <= nd * 2 )); then
        local wx=$(( gx + wcol + 2 - ${#wlbl} / 2 ))
        (( wx < gx )) && wx=$gx
        (( wx + ${#wlbl} > gx + nd * 2 )) && wx=$(( gx + nd * 2 - ${#wlbl} ))
        if (( gg_c0 < 0 || wx + ${#wlbl} <= gg_c0 || wx >= gg_c1 )); then
          scr_put "$mb" "$wx" ${#wlbl} "${FA}${wlbl}${RS}"
          break
        fi
      fi
      sat=$(( sat - 7 ))
    done
  fi

  # ── axis ──
  local axis_row=$((mb + 1)) q
  for q in 0 1 2 3; do
    local albl="-$(( nd - nd * q / 4 ))${unit}"
    scr_put "$axis_row" $(( gx + (nd * 2 - 6) * q / 4 )) ${#albl} "${FA}${albl}${RS}"
  done
  scr_put "$axis_row" $((gx + nd * 2 - 5)) 5 "${FA}today${RS}"

  # ── the cards anchor to the panel bottom; the meta text floats centered
  # in the space between the graph block and the cards, wrapping by chunk ──
  local sub_top=$(( ph - 1 - sub_h ))
  (( sub_top < axis_row + 2 )) && sub_top=$((axis_row + 2))
  local gap_top=$((axis_row + 1)) gap_bot=$((ph - 2))
  (( sub_h >= 9 )) && gap_bot=$((sub_top - 1))

  local VC2 WH
  VC2=$(fgt "$RGB_VOICE"); WH=$(fgt "255;255;255")
  local rested="" restc=""
  if (( ${P[REST_GAPS]:-0} > 0 )); then
    rested=" ✓ rested"; restc="$(fgt "$RGB_GREEN") ✓ rested${RS}"
  fi
  local -a mcp=("today ${P[EV_TODAY]:-0}" "peak ${P[EV_PEAK]:-0}" \
    "active ${P[ACTIVE21]:-0}/21d → fitness ${P[FITNESS]:-0}" \
    "quiet gaps ≥6h, last 24h: ${P[REST_GAPS]:-0}${rested}")
  local -a mcc=( \
    "${VC2}today ${WH}${C_BOLD}${P[EV_TODAY]:-0}${RS}" \
    "${VC2}peak ${WH}${C_BOLD}${P[EV_PEAK]:-0}${RS}" \
    "${VC2}active ${WH}${C_BOLD}${P[ACTIVE21]:-0}/21d${RS}${VC2} → fitness ${WH}${C_BOLD}${P[FITNESS]:-0}${RS}" \
    "${VC2}quiet gaps ≥6h, last 24h: ${WH}${C_BOLD}${P[REST_GAPS]:-0}${RS}${restc}")
  local -a mlp=() mlc=()
  local cur_p="" cur_c="" mi2
  for mi2 in "${!mcp[@]}"; do
    if [[ -z $cur_p ]]; then
      cur_p=${mcp[mi2]}; cur_c=${mcc[mi2]}
    elif (( ${#cur_p} + 3 + ${#mcp[mi2]} <= COLS - 4 )); then
      cur_p+="   ${mcp[mi2]}"; cur_c+="   ${mcc[mi2]}"
    else
      mlp+=("$cur_p"); mlc+=("$cur_c")
      cur_p=${mcp[mi2]}; cur_c=${mcc[mi2]}
    fi
  done
  [[ -n $cur_p ]] && { mlp+=("$cur_p"); mlc+=("$cur_c"); }
  local mtop=$(( gap_top + (gap_bot - gap_top + 1 - ${#mlp[@]}) / 2 ))
  (( mtop < gap_top )) && mtop=$gap_top
  local li
  for li in "${!mlp[@]}"; do
    (( mtop + li > gap_bot )) && break
    local mx2=$(( (COLS - ${#mlp[li]}) / 2 ))
    (( mx2 < gx )) && mx2=$gx
    scr_put $((mtop + li)) "$mx2" ${#mlp[li]} "${mlc[li]}"
  done

  # ── subgrid: weekday rhythm + 12-week calendar (mockup .subgrid) ──
  if (( sub_h >= 9 )); then
    local wk_w=$(( (COLS - 6) * 2 / 5 )) cal_x cal_w
    cal_x=$(( 2 + wk_w + 2 )); cal_w=$(( COLS - 4 - wk_w - 2 ))
    local wt="your rhythm · avg events by weekday (90d)"
    (( wk_w < ${#wt} + 8 )) && wt="your rhythm · by weekday (90d)"
    (( wk_w < ${#wt} + 8 )) && wt="rhythm"
    local ct="last 12 weeks · contribution calendar"
    (( cal_w < ${#ct} + 8 )) && ct="12 weeks · calendar"
    PF_TITLE_RGB=$RGB_MUTED
    panel_frame "$sub_top" 2 "$wk_w" "$sub_h" "$RGB_SEP" "$wt" ""
    PF_TITLE_RGB=$RGB_MUTED
    panel_frame "$sub_top" "$cal_x" "$cal_w" "$sub_h" "$RGB_SEP" "$ct" ""

    # weekday bars: boundary-spaced so the seven span the full card width;
    # tiny values keep a sliver so a quiet weekend reads as a feature
    local -a wk=(${P[WKDAY_X10]:-0 0 0 0 0 0 0})
    local wmax=1 wv
    for wv in "${wk[@]}"; do (( wv > wmax )) && wmax=$wv; done
    local brows=$(( sub_h - 3 )) winner=$(( wk_w - 4 ))
    local -a wlbls=(mon tue wed thu fri sat sun)
    (( winner / 7 < 4 )) && wlbls=(mo tu we th fr sa su)
    local d
    for ((r=0; r<brows; r++)); do
      for d in 0 1 2 3 4 5 6; do
        local x0=$(( winner * d / 7 ))
        local bw2=$(( winner / 7 - 1 )); (( bw2 < 1 )) && bw2=1
        local h8=$(( wk[d] * (brows - 1) * 8 / wmax ))   # headroom row on top
        local base8=$(( (brows - 1 - r) * 8 ))
        local f=$(( h8 - base8 )); (( f < 0 )) && f=0; (( f > 8 )) && f=8
        (( r == brows - 1 && f == 0 && wk[d] > 0 )) && f=1   # the sliver
        local ch=${EIGHTHS:f:1}
        [[ $ch == " " ]] && continue
        local brgb=$ACT_G3
        (( wk[d] * 100 / wmax < 25 )) && brgb=$ACT_G1
        scr_put $((sub_top + 1 + r)) $((4 + x0)) "$bw2" "$(fgt "$brgb")$(repeat_str "$ch" "$bw2")${RS}"
      done
    done
    for d in 0 1 2 3 4 5 6; do
      local x0=$(( winner * d / 7 ))
      local bw2=$(( winner / 7 - 1 )); (( bw2 < 1 )) && bw2=1
      local lx=$(( 4 + x0 + (bw2 - ${#wlbls[d]}) / 2 )); (( lx < 4 + x0 )) && lx=$((4 + x0))
      scr_put $((sub_top + 1 + brows)) "$lx" ${#wlbls[d]} "${FA}${wlbls[d]}${RS}"
    done

    # calendar: 12 columns of 7, boundary-spaced across the full card —
    # single background hairlines between cells, no end-cap artifacts
    local -a cal=(${P[CAL84]:-})
    local cmax=1 cvv
    for cvv in "${cal[@]}"; do (( cvv > cmax )) && cmax=$cvv; done
    local cinner=$(( cal_w - 4 )) w2
    for ((r=0; r<7; r++)); do
      (( sub_top + 1 + r >= sub_top + sub_h - 1 )) && break
      local cline="" prev=0
      for ((w2=0; w2<12; w2++)); do
        local cx0=$(( cinner * w2 / 12 )) cx1=$(( cinner * (w2 + 1) / 12 ))
        local cw=$(( cx1 - cx0 - 1 )); (( cw < 1 )) && cw=1
        local cv=${cal[w2 * 7 + r]:-0}
        cline+="$(repeat_str " " $((cx0 - prev)))$(fgt "$(act_shade "$cv" "$cmax")")$(repeat_str "▄" "$cw")${RS}"
        prev=$(( cx0 + cw ))
      done
      scr_put $((sub_top + 1 + r)) $((cal_x + 2)) "$prev" "$cline"
    done
  fi

  DFOOT_RIGHT="rhythm beats volume — the baseline is yours, not global"
  dense_footer $((LINES - 1)) "tab range" "esc back"
  scr_emit
}

# ══ feed · expanded — the liveness log (mockup §feed) ════════════════════════
# every entry names its event, its source and its effect on the pet; filter
# chips map to notification reasons; day headers group the log.

FEEDX_TAGS=(all merge review mention medal rest sec)
FEEDX_LABELS=(all merge review mention medal rest security)

declare -a DFEEDX=()
DFEEDX_KEY="§unset§"
dfeedx_load() { # FEEDX_RAW → DFEEDX[] (cached on the raw string)
  [[ $DFEEDX_KEY == "$1" ]] && return
  DFEEDX_KEY=$1
  DFEEDX=()
  local raw=$1
  while [[ $raw == *";;"* ]]; do
    DFEEDX+=("${raw%%;;*}")
    raw=${raw#*;;}
  done
  [[ -n $raw ]] && DFEEDX+=("$raw")
}

draw_feed_x() { # assoc_name self — 1:1 with the mockup's liveness log
  local -n P=$1
  local self=$2
  scr_reset
  local MU FA IN VC
  MU=$(fgt "$RGB_MUTED"); FA=$(fgt "$RGB_FAINT"); IN=$(fgt "$RGB_INK"); VC=$(fgt "$RGB_VOICE")
  local ph=$((LINES - 1))
  local ftitle="feed · live · ${TTL_FAST}s"
  [[ $self != 1 ]] && ftitle="feed · cache · 5m"
  panel_frame 0 0 "$COLS" "$ph" "$RGB_PURPLE" "$ftitle" "1-7 filter · esc back"
  dfeedx_load "${P[FEEDX_RAW]:-}"

  # ── filter chips (mockup .chips) ──
  local cx=2 ci
  for ci in "${!FEEDX_LABELS[@]}"; do
    local lb=" $((ci + 1)) ${FEEDX_LABELS[ci]} "
    (( cx + ${#lb} + 2 > COLS - 2 )) && break
    if (( ci == FEED_FILTER )); then
      scr_put 1 "$cx" $(( ${#lb} + 2 )) "$(fgt "$RGB_PURPLE")(${RS}${IN}${C_BOLD}${lb}${RS}$(fgt "$RGB_PURPLE"))${RS}"
    else
      scr_put 1 "$cx" $(( ${#lb} + 2 )) "${FA}(${RS}${MU}${lb}${RS}${FA})${RS}"
    fi
    cx=$(( cx + ${#lb} + 3 ))
  done

  # ── the log: every entry names its event, links its page, and narrates
  # what the pet did about it (mockup: how users learn the mechanics) ──
  local today yest now
  now=$(date +%s)
  printf -v today '%(%Y-%m-%d)T' "$now"
  printf -v yest '%(%Y-%m-%d)T' $(( now - 86400 ))
  local want=${FEEDX_TAGS[FEED_FILTER]}
  local er=3 lastday="§" n=0 ent
  local pnm=${P[NAME]:-the pet}
  FEEDX_N=0 FEEDX_SEL_URL=""
  for ent in "${DFEEDX[@]}"; do
    local daykey daylbl tm tag tx2 fxv furl fttl
    IFS='|' read -r daykey daylbl tm tag tx2 fxv furl fttl <<<"$ent"
    [[ $want != all && $tag != "$want" ]] && continue
    (( er >= ph - 5 )) && break
    if [[ $daykey != "$lastday" ]]; then
      if [[ $lastday != "§" ]]; then er=$((er + 1)); fi   # air above a new day
      lastday=$daykey
      local dl=$daylbl
      [[ $daykey == "$today" ]] && dl="today"
      [[ $daykey == "$yest" ]] && dl="yesterday"
      (( er >= ph - 5 )) && break
      scr_put "$er" 2 $(( ${#dl} + 6 )) "${FA}── ${dl} ──${RS}"
      er=$((er + 1))
      (( er >= ph - 5 )) && break
    fi
    # the pet's reaction + the door to the page (mockup: — link ↗ → reaction)
    local narr="" lnk=""
    case $tag in
      merge)   narr="→ ${pnm} ate";            lnk=${fttl:+"${fttl} ↗"} ;;
      review)  narr="→ pet holds the scroll";  [[ -n $furl ]] && lnk="open the PR ↗" ;;
      mention) narr="→ ✉" ;;
      sec)     narr="→ pet looks worried";     [[ -n $furl ]] && lnk="view alerts ↗" ;;
      rest)    narr="→ pet slept while you did" ;;
      medal)   narr="→ celebrate burst" ;;
    esac
    local full_p="${tx2}${lnk:+ — ${lnk}} ${narr}"
    local fxw=0; [[ -n $fxv ]] && fxw=$(( ${#fxv} + 2 ))
    local avail=$(( COLS - 4 - 6 - 10 - fxw ))
    local txc
    local rowlink=1
    local WH; WH=$(fgt "255;255;255")
    if (( ${#full_p} > avail )); then
      # scrolling rows still get their facts lit — refs matched in whatever
      # slice is visible this tick
      full_p=$(marquee "$full_p" "$avail" "$er")
      local VXHL
      vx_hl "$full_p" '[A-Za-z0-9._/-]*#[0-9]+' "${WH}${C_BOLD}" $'\e[22m'"${VC}"
      txc="${VC}${VXHL}${RS}"
    else
      # styled: white-hot facts (mockup .fev .tx b), each deep-linked —
      # the PR number opens the PR, the repo name opens the repo
      rowlink=0
      if [[ $tag == merge && $tx2 =~ ^PR\ (#[0-9]+)\ merged\ in\ (.+)$ ]]; then
        local rurl=""
        [[ $furl == *"/pull/"* ]] && rurl=${furl%/pull/*}
        txc="${VC}PR $(osc8 "$furl" "${WH}${C_BOLD}${BASH_REMATCH[1]}${RS}")${VC} merged in $(osc8 "$rurl" "${WH}${C_BOLD}${BASH_REMATCH[2]}${RS}")"
      elif [[ $tag =~ ^(review|mention|sec)$ && $tx2 == *" · "* ]]; then
        txc="${VC}${tx2%% · *} · $(osc8 "$furl" "${WH}${C_BOLD}${tx2#* · }${RS}")"
      else
        txc="${VC}${tx2}${RS}"
      fi
      [[ -n $lnk ]] && txc+="${VC} — ${RS}$(osc8 "$furl" "$(fgt "$RGB_BLUE")"$'\e[4m'"${lnk}"$'\e[24m'"${RS}")"
      txc+="${VC} ${narr}${RS}"
    fi
    local FCHIP; feed_tag_chip "$tag"
    local tpad=$(( 10 - ${#tag} - 2 )); (( tpad < 0 )) && tpad=0
    local line
    if (( rowlink )); then    # scrolling rows keep the single whole-row link
      line="${FA}$(printf '%-6s' "$tm")${RS}$(osc8 "$furl" "${FCHIP}$(repeat_str " " "$tpad")${txc}")"
    else
      line="${FA}$(printf '%-6s' "$tm")${RS}$(osc8 "$furl" "${FCHIP}")$(repeat_str " " "$tpad")${txc}"
    fi
    # the effect rides the right edge (mockup .fev .fx)
    local pad=$(( COLS - 4 - 6 - 10 - ${#full_p} - fxw ))
    (( pad < 0 )) && pad=0
    line+=$(repeat_str " " "$pad")
    if [[ -n $fxv ]]; then
      local fxc=$RGB_GREEN; [[ ${fxv:0:1} == "−" ]] && fxc=$RGB_RED
      line+="  $(fgt "$fxc")${C_BOLD}${fxv}${RS}"
    fi
    if (( n == SEL_FEED )); then     # selected row: soft purple tint
      local selbg=$'\e[48;2;30;24;44m'
      line="${selbg}${line//$'\e[0m'/$'\e[0m'${selbg}}"$'\e[49m'
      FEEDX_SEL_URL=$furl
    fi
    scr_put "$er" 2 $(( COLS - 4 )) "$line"
    er=$((er + 1)); n=$((n + 1))
  done
  FEEDX_N=$n
  if (( n == 0 )); then
    local none="no ${FEEDX_LABELS[FEED_FILTER]} events in the window — the pet naps"
    scr_put 4 2 ${#none} "${MU}${none}${RS}"
  fi

  # ── poll note (mockup .pollnote): the budget, above a dashed rule ──
  scr_put $((ph - 4)) 2 $((COLS - 4)) "$(fgt "$RGB_SEP")$(repeat_str "╌" $((COLS - 4)))${RS}"
  local used="–" rem
  rem=$(api_remaining)
  [[ $rem =~ ^[0-9]+$ ]] && (( rem <= 5000 )) && used=$((5000 - rem))
  local l1="poll: ${TTL_FAST}s per X-Poll-Interval · If-Modified-Since/ETag · 304s don't count against rate limit — staying alive costs ~0 ·"
  if (( ${#l1} <= COLS - 4 )); then
    scr_put $((ph - 3)) 2 ${#l1} \
      "${FA}poll: ${TTL_FAST}s per ${RS}$(fgt "$RGB_CYAN")X-Poll-Interval${RS}${FA} · If-Modified-Since/ETag · 304s don't count against rate limit — staying alive costs ~0 ·${RS}"
  else
    l1=$(marquee "$l1" $((COLS - 4)) 5)
    scr_put $((ph - 3)) 2 ${#l1} "${FA}${l1}${RS}"
  fi
  local l2="api ${used}/5000 · search tier untouched (30/min cap)"
  scr_put $((ph - 2)) 2 ${#l2} \
    "${FA}api ${RS}$(fgt "$RGB_GREEN")${C_BOLD}${used}${RS}${FA}/5000 · search tier untouched (30/min cap)${RS}"

  # ── footer: ↵ open · esc back — next poll countdown on the right ──
  if [[ -z ${FIXDIR:-} && $self == 1 ]]; then
    local npoll=$(( NEXT_REFRESH - now ))
    (( npoll < 0 )) && npoll=0
    (( npoll > TTL_FAST )) && npoll=$TTL_FAST
    DFOOT_RIGHT_P="${G_SPIN} next poll in ${npoll}s"
    DFOOT_RIGHT_C="$(fgt "$RGB_GREEN")${G_SPIN} next poll${RS}${MU} in ${npoll}s${RS}"
  fi
  dense_footer $((LINES - 1)) "↵ open link" "esc back"
  scr_emit
}

# ══ friends · expanded — the crowd + preview (mockup §friends) ═══════════════
# left: the full following table, awake by happiness, hibernators sunk to the
# bottom with day counts. right: the selected friend rendered live from the
# 5-minute cache — pixel pet, stats, medals, and "private · by design".

draw_friends_x() {
  scr_reset
  local MU FA IN
  MU=$(fgt "$RGB_MUTED"); FA=$(fgt "$RGB_FAINT"); IN=$(fgt "$RGB_INK")
  local ph=$((LINES - 1))
  local two=0 lw=$COLS
  (( COLS >= 76 )) && { two=1; lw=$(( COLS * 55 / 100 )); }
  panel_frame 0 0 "$lw" "$ph" "$RGB_BLUE" "following · ${#FR_LOGINS[@]}" "jk · ↵ visit"
  local fx=2 fiw=$((lw - 4))   # tight gutter: content hugs the border by 1

  # sprite rows (mockup: real pixel pets in the list) need pixel support and
  # 3 rows per awake pet; hibernators/eggs stay one line, like the mockup.
  # Column offsets adapt: wide (fiw ≥ 56) and narrow (≥ 44) sprite layouts.
  local srows=0
  local -a fxh=()   # per-row draw heights, feeds the scrolling viewport
  local flw=14 fsx=16 fnx=25 fnw=10 flx=35 flvw=8 fhx=43 fstx=56
  if (( fiw < 56 )); then flw=10 fsx=12 fnx=21 fnw=9 flx=31 flvw=6 fhx=38 fstx=51; fi
  if (( fiw < 50 )); then flx=21 flvw=6 fhx=27 fstx=40; fi   # tiny: state col drops
  if [[ -n $PIX_MODE ]] && (( fiw >= 39 )); then   # tiny needs 39 (❤ col + 12)
    # sprite rows at ANY list length — the viewport scrolls instead of
    # falling back to cramped single lines when the crowd outgrows the panel
    srows=1
    local need=0 naw=0 l2 rd f5
    for l2 in "${FR_SORTED[@]}"; do
      rd=${FRROW[$l2]:-}
      if [[ -n $rd ]]; then
        f5=${rd#*|}; f5=${f5#*|}; f5=${f5#*|}; f5=${f5#*|}; f5=${f5%%|*}
        if [[ $f5 == "-" ]]; then need=$((need + 2)); naw=$((naw + 1)); fxh+=(2); else need=$((need + 1)); fxh+=(1); fi
      else need=$((need + 1)); fxh+=(1); fi
    done
    local fgap=0   # sprite blocks stack directly, no breathing row between
  fi
  local fbnw=12 fbvw=7
  if (( ! srows )); then                       # fallback columns, budgeted
    flw=14
    (( fiw < 52 )) && { flw=10; fbnw=8; }
    (( fiw < 44 )) && fbnw=0
    (( fiw < 33 )) && fbvw=0
    fsx=$(( 2 + flw ))
    flx=$(( fsx + 4 + fbnw ))
    fhx=$(( flx + fbvw ))
    fstx=$(( fhx + 13 ))
  fi

  # header: one segment per column, clipped at the panel edge so nothing
  # ever paints across the borders
  hput() { # x text color
    local hx2=$1 htx=$2 hc=$3
    (( fx + hx2 + ${#htx} <= fx + fiw )) || return 0
    scr_put 1 $(( fx + hx2 )) ${#htx} "${hc}${htx}${RS}"
  }
  hput 2 "login" "$FA"
  hput "$fsx" "pet" "$FA"
  (( srows || fbvw > 0 )) && hput "$flx" "lvl" "$FA"
  hput "$fhx" "${G_HEART} happy ▾" "$(fgt "$RGB_BLUE")"
  (( fstx + 5 <= fiw )) && hput "$fstx" "state" "$FA"
  local frow=3 i
  # single-line fallback rows are single-spaced — no blank line between
  local fpitch=1
  if (( ${#FR_SORTED[@]} == 0 )); then
    scr_put 4 "$fx" $((fiw - 1)) "${MU}$(trunc "Follow someone on GitHub and their pet appears here." $((fiw - 1)))${RS}"
    scr_put 5 "$fx" $((fiw - 1)) "${MU}$(trunc "A friend's pet is computed from their public account." $((fiw - 1)))${RS}"
  fi
  # ── scrolling viewport (session view state): the window follows the jk
  # cursor; wrap-around selection makes the list feel endless ──
  local fN=${#FR_SORTED[@]} j3
  if (( ! srows )); then fxh=(); for ((j3=0; j3<fN; j3++)); do fxh+=("$fpitch"); done; fi
  if (( fN > 0 )); then
    # the last row carries no trailing gap — don't let a phantom gap
    # push an exactly-fitting list into scroll mode
    (( ! srows )) && fxh[fN-1]=1
    (( srows && fxh[fN-1] == 3 )) && fxh[fN-1]=2
    (( SEL_FRIEND >= fN )) && SEL_FRIEND=$(( fN - 1 ))
  fi
  local -a fpre=(0); local hsum=0
  for j3 in "${!fxh[@]}"; do hsum=$((hsum + fxh[j3])); fpre+=("$hsum"); done
  local farea=$(( ph - 4 ))              # list rows 3 .. ph-2
  (( fN > 0 && fpre[fN] > farea )) && farea=$((farea - 1))   # reserve the more-line
  (( SEL_FRIEND < ${FRX_OFF:-0} )) && FRX_OFF=$SEL_FRIEND
  while (( ${FRX_OFF:-0} < SEL_FRIEND && fpre[SEL_FRIEND+1] - fpre[FRX_OFF] > farea )); do
    FRX_OFF=$((FRX_OFF + 1))
  done
  # never waste bottom space the tail could fill
  while (( ${FRX_OFF:-0} > 0 && fpre[fN] - fpre[FRX_OFF-1] <= farea )); do
    FRX_OFF=$((FRX_OFF - 1))
  done
  (( ${FRX_OFF:-0} < 0 )) && FRX_OFF=0
  # top indicator lives in the divider so it costs no list row
  if (( ${FRX_OFF:-0} > 0 )); then
    local dtx=" ↑ ${FRX_OFF} more "
    scr_put 2 "$fx" "$fiw" "$(fgt "$RGB_SEP")$(repeat_str "─" $(( fiw - ${#dtx} - 2 )))${RS}${MU}${dtx}${RS}$(fgt "$RGB_SEP")──${RS}"
  else
    scr_put 2 "$fx" "$fiw" "$(fgt "$RGB_SEP")$(repeat_str "─" "$fiw")${RS}"
  fi
  local flim=$(( 3 + farea )) fdrawn=-1
  for i in "${!FR_SORTED[@]}"; do
    (( i < ${FRX_OFF:-0} )) && continue
    (( frow + fxh[i] > flim )) && break
    fdrawn=$i
    local login=${FR_SORTED[i]}
    local rowd=${FRROW[$login]:-}
    local selp="  " logc=$IN line vis
    (( i == SEL_FRIEND )) && { selp="$(fgt "$RGB_BLUE")${G_SEL} ${RS}"; logc="$(fgt "$RGB_BLUE")${C_BOLD}"; }
    if [[ -z $rowd ]]; then
      line="${selp}$(osc8 "https://github.com/$login" "${logc}$(printf "%-${flw}s" "$(trunc "$login" "$flw")")${RS}")${FA}···${RS}"
      vis=$(( 2 + flw + 3 ))
      scr_put "$frow" "$fx" "$vis" "$line"
      frow=$((frow + (srows ? 1 : fpitch)))
      continue
    fi
    local pname=${rowd%%|*} q2=${rowd#*|}
    local mini=${q2%%|*} q3=${q2#*|}
    local c256=${q3%%|*} q4=${q3#*|}
    local happy=${q4%%|*} q5=${q4#*|}
    local state=${q5%%|*} q6=${q5#*|}
    local stage=${q6%%|*} q7=${q6#*|}
    local species=${q7%%|*} chex=${q7#*|}
    local hv=${happy:-0} hrgb=$RGB_GREEN
    (( hv < 50 )) && hrgb=$RGB_YELLOW
    (( hv < 20 )) && hrgb=$RGB_RED

    if (( srows )) && [[ $state == "-" ]] && pix_render_mini "$species" "$chex"; then
      # ── mockup row: pixel pet on two lines, name at its paw ──
      local rA rB
      rA="${selp}$(osc8 "https://github.com/$login" "${logc}$(printf "%-${flw}s" "$(trunc "$login" "$flw")")${RS}")"
      rA+="${PIXM[0]}$(repeat_str " " $(( flx - fsx - 6 )))${MU}$(padw "$(trunc "$stage" $((flvw - 1)))" $(( fhx - flx )))${RS}"
      dmeter "$hv" 8
      rA+="${DM} $(fgt "$hrgb")${C_BOLD}$(printf '%-3s' "$hv")${RS}"
      rB="$(repeat_str " " "$fsx")${PIXM[1]} ${MU}$(padw "$(marquee "$pname" "$fnw" "$i")" "$fnw")${RS}"
      local vA=$(( fhx + 8 + 1 + 3 )) vB=$(( fsx + 6 + 1 + fnw ))
      if (( i == SEL_FRIEND )); then     # tint spans the whole block
        local selbg=$'\e[48;2;22;35;58m' rr
        local -a rls=("$rA" "$rB") rvs=("$vA" "$vB")
        for rr in 0 1; do
          local pad=$(( fiw - rvs[rr] )); (( pad < 0 )) && pad=0
          rls[rr]="${selbg}${rls[rr]//$'\e[0m'/$'\e[0m'${selbg}}$(repeat_str " " "$pad")"$'\e[49m'
          rvs[rr]=$fiw
        done
        rA=${rls[0]}; rB=${rls[1]}
        vA=${rvs[0]}; vB=${rvs[1]}
      fi
      scr_put "$frow" "$fx" "$vA" "$rA"
      scr_put $((frow + 1)) "$fx" "$vB" "$rB"
      frow=$((frow + 2 + fgap))
      continue
    fi

    if (( srows )); then
      # hibernators and eggs: one quiet line, columns aligned with the blocks
      local dispname=$pname
      [[ $state == egg:* ]] && dispname="—"
      line="${selp}$(osc8 "https://github.com/$login" "${logc}$(printf "%-${flw}s" "$(trunc "$login" "$flw")")${RS}")"
      line+="${MU}$(padw "$(trunc "$dispname" $(( flx - fsx - 1 )))" $(( flx - fsx )))${RS}"
      line+="${MU}$(padw "$(trunc "$stage" $((flvw - 1)))" $(( fhx - flx )))${RS}"
      vis=$(( fhx ))
      local srem=$(( fiw - fstx )) sdash=$(( fstx - fhx ))
      if (( srem < 6 )); then sdash=0; srem=$(( fiw - fhx )); fi
      case $state in
        hib:*)
          local htxt="${G_ZZZ} hibernating · ${state#hib:}d"
          (( srem < ${#htxt} )) && htxt="${G_ZZZ} hib · ${state#hib:}d"
          htxt=$(trunc "$htxt" "$srem")
          (( sdash )) && line+="${FA}$(padw "—" "$sdash")${RS}"
          line+="$(fgt "$RGB_ICE")${htxt}${RS}"
          vis=$(( fhx + sdash + ${#htxt} )) ;;
        egg:*)
          local etxt="hatches in ${state#egg:}d"
          etxt=$(trunc "$etxt" "$srem")
          (( sdash )) && line+="${FA}$(padw "—" "$sdash")${RS}"
          line+="$(fgt "$RGB_YELLOW")${etxt}${RS}"
          vis=$(( fhx + sdash + ${#etxt} )) ;;
      esac
      if (( i == SEL_FRIEND )); then
        local selbg=$'\e[48;2;22;35;58m'
        local pad=$(( fiw - vis )); (( pad < 0 )) && pad=0
        line="${selbg}${line//$'\e[0m'/$'\e[0m'${selbg}}$(repeat_str " " "$pad")"$'\e[49m'
        vis=$fiw
      fi
      scr_put "$frow" "$fx" "$vis" "$line"
      frow=$((frow + 1))
      continue
    fi

    # ── fallback: single-line rows, assembled only up to the budget ──
    [[ $state == hib:* ]] && mini="(-)"       # cocooned, face hidden
    if [[ $state == egg:* ]]; then mini="(${G_SPARK})"; pname="—"; fi
    line="${selp}$(osc8 "https://github.com/$login" "${logc}$(printf "%-${flw}s" "$(trunc "$login" "$flw")")${RS}")"
    vis=$(( 2 + flw ))
    line+="$(fg "$c256")$(padw "$mini" 4)${RS}"
    vis=$(( vis + 4 ))
    if (( fbnw > 0 )); then
      line+="${MU}$(padw "$(marquee "$pname" $((fbnw - 1)) "$i")" "$fbnw")${RS}"
      vis=$(( vis + fbnw ))
    fi
    if (( fbvw > 0 )); then
      line+="${MU}$(padw "$(trunc "$stage" $((fbvw - 1)))" "$fbvw")${RS}"
      vis=$(( vis + fbvw ))
    fi
    local remv=$(( fiw - vis ))
    case $state in
      hib:*)
        local htxt="${G_ZZZ} hibernating · ${state#hib:}d"
        (( remv < ${#htxt} + 13 )) && htxt="${G_ZZZ} hib · ${state#hib:}d"
        if (( remv >= ${#htxt} + 13 )); then
          line+="${FA}$(padw "—" 13)${RS}"; vis=$((vis + 13)); remv=$((remv - 13))
        fi
        htxt=$(trunc "$htxt" "$remv")
        line+="$(fgt "$RGB_ICE")${htxt}${RS}"; vis=$(( vis + ${#htxt} )) ;;
      egg:*)
        local etxt="hatches in ${state#egg:}d"
        if (( remv >= ${#etxt} + 13 )); then
          line+="${FA}$(padw "—" 13)${RS}"; vis=$((vis + 13)); remv=$((remv - 13))
        fi
        etxt=$(trunc "$etxt" "$remv")
        line+="$(fgt "$RGB_YELLOW")${etxt}${RS}"; vis=$(( vis + ${#etxt} )) ;;
      *)
        if (( remv >= 12 )); then
          dmeter "$hv" 8
          line+="${DM} $(fgt "$hrgb")${C_BOLD}$(printf '%-3s' "$hv")${RS}"
          vis=$(( vis + 12 ))
        fi ;;
    esac
    if (( i == SEL_FRIEND )); then
      local selbg=$'\e[48;2;22;35;58m'
      local pad=$(( fiw - vis )); (( pad < 0 )) && pad=0
      line="${selbg}${line//$'\e[0m'/$'\e[0m'${selbg}}$(repeat_str " " "$pad")"$'\e[49m'
      vis=$fiw
    fi
    scr_put "$frow" "$fx" "$vis" "$line"
    frow=$((frow + fpitch))
  done
  if (( fN > 0 && fdrawn < fN - 1 )); then
    local fbelow=$(( fN - fdrawn - 1 ))
    scr_put $(( flim )) "$fx" "$fiw" "${MU}$(trunc "↓ ${fbelow} more" "$fiw")${RS}"
  fi

  # ── preview pane: rendered from the cache, no network on keystroke ──
  if (( two )); then
    local rx=$((lw + 1)) rw2=$((COLS - lw - 1))
    local sel_login=${FR_SORTED[SEL_FRIEND]:-}
    if [[ -n $sel_login && $PV_LOGIN != "$sel_login" && -f $CACHE_ROOT/$sel_login/state.env ]]; then
      load_state PV "$sel_login" && PV_LOGIN=$sel_login
    fi
    if [[ -n $sel_login && $PV_LOGIN == "$sel_login" ]]; then
      local prgb; prgb=$(hex_to_rgb "${PV[COLOR_HEX]:-#dea584}")
      local pnm; pnm=$(tr '[:upper:]' '[:lower:]' <<<"${PV[NAME]}")
      panel_frame 0 "$rx" "$rw2" "$ph" "$prgb" "@${sel_login} · ${pnm}" "preview"
      local px0=$((rx + 2)) piw=$((rw2 - 4))
      local frz=${PV[HIB]:-0}
      # stage: the pet up top on a dotted line (mockup .preview .stage)
      local ground
      if [[ ${PV[STAGE]:-} == egg ]]; then
        local tilt=0
        (( (TICK / 8) % 4 == 1 )) && tilt=-1
        (( (TICK / 8) % 4 == 3 )) && tilt=1
        if [[ -n $PIX_MODE && -n ${PIXF[egg/idle_1]:-} ]]; then
          pix_palette egg "${PV[COLOR_HEX]:-#dea584}" 0
          pix_render egg idle_1 0 0 0
          local eh=$PIXOUT_H ei
          ground=$(( 2 + eh )); (( ground > ph - 12 )) && ground=$(( ph - 12 ))
          local etop=$(( ground - eh )); (( etop < 1 )) && etop=1
          local ex2=$(( px0 + (piw - PIXOUT_W) / 2 + tilt ))
          (( ex2 < px0 )) && ex2=$px0
          for ((ei=0; ei<eh; ei++)); do
            (( etop + ei >= ground )) && break
            scr_put $((etop + ei)) "$ex2" "$PIXOUT_W" "${PIXOUT[ei]}"
          done
        else
          egg_frame "$tilt" "$(fg "${PV[COLOR256]:-180}")"
          local eh=${#SPCOMP_PLAIN[@]} ei
          ground=$(( 2 + eh )); (( ground > ph - 12 )) && ground=$(( ph - 12 ))
          local etop=$(( ground - eh )); (( etop < 1 )) && etop=1
          for ei in "${!SPCOMP_PLAIN[@]}"; do
            (( etop + ei >= ground )) && break
            local ew=${#SPCOMP_PLAIN[ei]}
            scr_put $((etop + ei)) $(( px0 + (piw - ew) / 2 )) "$ew" "${SPCOMP_COL[ei]}"
          done
        fi
      else
        local pframe="idle_$(( (TICK / 3) % 2 + 1 ))"
        [[ $frz == 1 ]] && pframe="hibernate_$(( (TICK / 6) % 2 + 1 ))"
        pet_compose PV "$pframe" 0 0
        ground=$(( 2 + PET_H )); (( ground > ph - 12 )) && ground=$(( ph - 12 ))
        local ptop=$(( ground - PET_H )) pi skip=0
        if (( ptop < 1 )); then skip=$(( 1 - ptop )); ptop=1; fi
        local petx=$(( px0 + (piw - PET_W) / 2 )); (( petx < px0 )) && petx=$px0
        for ((pi=skip; pi<PET_H; pi++)); do
          (( ptop + pi - skip >= ground )) && break
          scr_put $((ptop + pi - skip)) "$petx" "$PET_W" "${PET_LINES[pi]}"
        done
      fi
      scr_put "$ground" "$px0" "$piw" "$(fgt "$RGB_SEP")$(repeat_str "┄" "$piw")${RS}"
      local pr=$((ground + 1))
      # nameplate rows, centered like the mockup preview
      local nmx=$(( px0 + (piw - ${#PV[NAME]}) / 2 ))
      scr_put "$pr" "$nmx" ${#PV[NAME]} "${IN}${C_BOLD}${PV[NAME]}${RS}"; pr=$((pr + 1))
      local meta="the ${PV[SPECIES_LABEL]:-${PV[SPECIES]}} · ${PV[STAGE]} · est. ${PV[CREATED_YEAR]}"
      meta=$(trunc "$meta" "$piw")
      scr_put "$pr" $(( px0 + (piw - ${#meta}) / 2 )) ${#meta} "${MU}${meta}${RS}"; pr=$((pr + 2))
      local lang_lc; lang_lc=$(tr '[:upper:]' '[:lower:]' <<<"${PV[TOP_LANG]:-?} ${PV[COLOR_HEX]}")
      local chip="[ ■ ${lang_lc} ]"
      scr_put "$pr" $(( px0 + (piw - ${#chip}) / 2 )) ${#chip} \
        "$(fgt "$prgb")${C_DIM}[ ${RS}$(fgt "$prgb")■ ${lang_lc}${RS}$(fgt "$prgb")${C_DIM} ]${RS}"
      pr=$((pr + 2))
      # five mini rows: enough to gossip, not enough to surveil
      local -a pkeys=(HAPPINESS HUNGER ENERGY FITNESS SOCIAL)
      local -a pnames=(happy hunger energy fitness social)
      local pk
      local ppitch=1
      (( ph - pr >= 2 * ${#pkeys[@]} + 6 )) && ppitch=2   # breathing room
      for pk in "${!pkeys[@]}"; do
        (( pr >= ph - 3 )) && break
        local pv2=${PV[${pkeys[pk]}]:-0}
        dmeter "$pv2" 8 "$frz"
        local prpad=$(( piw - 2 - 8 - 8 - 3 - frz ))
        (( prpad < 1 )) && prpad=1
        scr_put "$pr" $((px0 + 1)) $(( 8 + 8 + prpad + 3 + frz )) \
          "${MU}$(printf '%-8s' "${pnames[pk]}")${RS}${DM}$(repeat_str " " "$prpad")$(dval "$pv2" "$frz")"
        pr=$((pr + ppitch))
      done
      # medal chips in their own colors, then the privacy stance
      if [[ ${PV[MEDALS_OK]:-0} == 1 && -n ${PV[MEDALS_RAW]:-} ]] && (( pr < ph - 2 )); then
        local mrow_p="" mrow_c="" m IFS=';'
        for m in ${PV[MEDALS_RAW]}; do
          local mc; mc=$(medal_code "${m%%|*}")
          local mlb=$mc
          (( ${m##*|} > 1 )) && mlb+=" ×${m##*|}"
          local cand="[${mlb}]"
          (( ${#mrow_p} + ${#cand} + 1 > piw )) && break
          mrow_p+="${mrow_p:+ }${cand}"
          mrow_c+="${mrow_c:+ }$(fgt "$RGB_YELLOW")[${C_BOLD}${mlb}"$'\e[22m'"]${RS}"
        done
        unset IFS
        [[ -n $mrow_p ]] && scr_put "$pr" $(( px0 + (piw - ${#mrow_p}) / 2 )) ${#mrow_p} \
          "$(osc8 "https://github.com/${sel_login}?tab=achievements" "$mrow_c")"
        pr=$((pr + 1))
      fi
      if (( pr <= ph - 2 )); then
        local priv="health · ─ private, by design"
        scr_put "$pr" $(( px0 + (piw - ${#priv}) / 2 )) ${#priv} "${FA}${priv}${RS}"
      fi
    else
      panel_frame 0 "$rx" "$rw2" "$ph" "$RGB_FAINT" "preview" ""
      local wait="··· fetching from the friend cache"
      (( ${#FR_SORTED[@]} == 0 )) && wait="no one to preview yet"
      scr_put $((ph / 2)) $(( rx + (rw2 - ${#wait}) / 2 )) ${#wait} "${FA}${wait}${RS}"
    fi
  fi

  DFOOT_RIGHT_P="✓ friend cache · 5m"
  DFOOT_RIGHT_C="$(fgt "$RGB_GREEN")✓ friend cache${RS}$(fgt "$RGB_MUTED") · 5m${RS}"
  dense_footer $((LINES - 1)) "jk move" "↵ visit" "c compare" "esc back"
  scr_emit
}
