# gitagotchi — lib/sprites.sh
# Sprite file parser + draw-time layered composition (design.md §6.1):
#   1. base frame (species file, face slot = @@@)
#   2. pattern layer (mask-marked body-interior cells)
#   3. accessory (at declared neck/head anchor)
#   4. face (3 chars into the @@@ slot, mood table §6.5)
#   5. color (whole sprite tinted with the linguist ANSI color)

declare -A SPRDB SPRDB_MINI SPRDB_NECK SPRDB_HEAD
declare -A SPR_LOADED

sprite_load() { # species
  local sp=$1
  [[ -n ${SPR_LOADED[$sp]:-} ]] && return 0
  local f="$SPRITE_DIR/$sp.sprite"
  [[ -r $f ]] || die "missing sprite: $f"
  local line block="" buf=""
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ -n $block ]]; then
      if [[ $line == "@end" ]]; then
        SPRDB["$sp/$block"]=${buf%$'\n'}; block="" buf=""
      else buf+="$line"$'\n'; fi
    else
      case $line in
        "#"*|"") ;;
        mini\ *)  SPRDB_MINI[$sp]=${line#mini } ;;
        neck\ *)  SPRDB_NECK[$sp]=${line#neck } ;;
        head\ *)  SPRDB_HEAD[$sp]=${line#head } ;;
        @*)       block=${line#@} ;;
      esac
    fi
  done < "$f"
  SPR_LOADED[$sp]=1
}

sprite_mini() { sprite_load "$1"; printf '%s' "${SPRDB_MINI[$1]:-??}"; }

# frames where the body is position-stable → pattern layer allowed
_pattern_ok() { case $1 in idle_1|idle_2|sleep_1|sleep_2|belly|stretch|sick) return 0;; *) return 1;; esac; }

# compose_sprite: fills SPCOMP_PLAIN[] (uncolored, for width math / snapshots)
# and SPCOMP_COL[] (with SGR + tint).
# args: species frame face pattern accessory tint_seq elder(0/1) faint(0/1)
declare -a SPCOMP_PLAIN SPCOMP_COL
compose_sprite() {
  local sp=$1 frame=$2 face=$3 pattern=$4 acc=$5 tint=$6 elder=$7 faint=$8
  sprite_load "$sp"
  local key="$sp/$frame"
  [[ -z ${SPRDB[$key]:-} ]] && key="$sp/idle_1"   # optional frames fall back
  local -a lines attr
  local IFS=$'\n'
  lines=(${SPRDB[$key]})
  unset IFS

  local nl=${#lines[@]} i j
  # attr strings parallel each line: .=body F=face P=pattern A=accessory
  for ((i=0; i<nl; i++)); do
    attr[i]=$(repeat_str "." "${#lines[i]}")
  done

  # ── face slot ──
  local face_r=-1 face_c=-1
  for ((i=0; i<nl; i++)); do
    local pos=${lines[i]%%@@@*}
    if [[ ${lines[i]} == *"@@@"* ]]; then
      face_r=$i face_c=${#pos}
      lines[i]=${lines[i]/@@@/$face}
      attr[i]="${attr[i]:0:face_c}FFF${attr[i]:face_c+3}"
      break
    fi
  done

  # ── pattern layer (only on stable frames; solid = no chars) ──
  if [[ $pattern != solid ]] && _pattern_ok "$frame" && [[ -n ${SPRDB[$sp/mask]:-} ]]; then
    local -a mask
    IFS=$'\n' mask=(${SPRDB[$sp/mask]}); unset IFS
    local run=0
    for ((i=0; i<nl && i<${#mask[@]}; i++)); do
      local ml=${mask[i]} ln=${lines[i]} at=${attr[i]}
      for ((j=0; j<${#ml}; j++)); do
        [[ ${ml:j:1} == "#" ]] || { run=0; continue; }
        # pad line if mask reaches past it
        while (( ${#ln} <= j )); do ln+=" "; at+="."; done
        local ch=""
        case $pattern in
          spots)   (( (j + i) % 2 == 0 )) && ch=$G_SPOT1 || { (( (j + i) % 4 == 1 )) && ch=$G_SPOT2; } ;;
          stripes) ch=$G_STRIPE ;;
          patches) (( run % 4 < 2 )) && ch=$G_PATCH ;;
        esac
        run=$((run+1))
        if [[ -n $ch ]]; then
          ln="${ln:0:j}$ch${ln:j+1}"; at="${at:0:j}P${at:j+1}"
        fi
      done
      lines[i]=$ln; attr[i]=$at
    done
  fi

  # ── accessory ──
  if [[ $acc != bare && -n $acc ]]; then
    local glyph anchor
    case $acc in
      bandana) glyph=$G_ACC_BANDANA; anchor=${SPRDB_NECK[$sp]:-} ;;
      bowtie)  glyph=$G_ACC_BOWTIE;  anchor=${SPRDB_NECK[$sp]:-} ;;
      collar)  glyph=$G_ACC_COLLAR;  anchor=${SPRDB_NECK[$sp]:-} ;;
      crown)   glyph=$G_ACC_CROWN;   anchor=${SPRDB_HEAD[$sp]:-} ;;
      *) glyph="" ;;
    esac
    if [[ -n $glyph && -n $anchor ]]; then
      local ar=${anchor%% *} ac=${anchor##* }
      if (( ar < nl )); then
        local ln=${lines[ar]} at=${attr[ar]}
        while (( ${#ln} < ac + 3 )); do ln+=" "; at+="."; done
        lines[ar]="${ln:0:ac}$glyph${ln:ac+3}"
        attr[ar]="${at:0:ac}AAA${at:ac+3}"
      fi
    fi
  fi

  # ── elder beard: ≡ under the chin (design.md §6.7) ──
  if [[ $elder == 1 && $face_r -ge 0 && $((face_r+1)) -lt $nl ]]; then
    local br=$((face_r+1)) bc=$((face_c+1))
    local ln=${lines[br]} at=${attr[br]}
    while (( ${#ln} <= bc )); do ln+=" "; at+="."; done
    local beard="≡"; [[ $TIER == A ]] && beard="="
    lines[br]="${ln:0:bc}$beard${ln:bc+1}"
    attr[br]=$at
  fi

  # ── colorize ──
  SPCOMP_PLAIN=() SPCOMP_COL=()
  local dimseq=$C_DIM
  [[ $faint == 1 ]] && tint="$tint$C_DIM"   # sick/hibernating: same hue + faint SGR (§2.2)
  for ((i=0; i<nl; i++)); do
    local ln=${lines[i]} at=${attr[i]} out="" cur="" seg="" k a
    SPCOMP_PLAIN+=("$ln")
    for ((k=0; k<${#ln}; k++)); do
      a=${at:k:1}
      local want
      case $a in
        F) want="${tint}${C_BOLD}" ;;
        P) want="${tint}${dimseq}" ;;
        A) want="${C_ACC}" ;;
        *) want="$tint" ;;
      esac
      if [[ $want != "$cur" ]]; then
        [[ -n $seg ]] && out+="${cur}${seg}${RS}"
        cur=$want seg=""
      fi
      seg+=${ln:k:1}
    done
    [[ -n $seg ]] && out+="${cur}${seg}${RS}"
    SPCOMP_COL+=("$out")
  done
  SPCOMP_FACE_R=$face_r
}

# global frames (design.md §6.1: cocoon + egg are global, tinted per-pet)
# cocoon breathing: 2 widths (expand/contract 1 char every 4 ticks, §2.3)
cocoon_frame() { # $1 = 0|1 phase → sets SPCOMP_PLAIN/COL, tint $2
  local tint=$2
  if [[ $1 == 0 ]]; then
    SPCOMP_PLAIN=( "  ⎛⎛ zZ ⎞⎞" " ⎛⎛ (-.-) ⎞⎞" "  ⎝⎝______⎠⎠" )
  else
    SPCOMP_PLAIN=( "  ⎛⎛  zZ  ⎞⎞" " ⎛⎛  (-.-)  ⎞⎞" "  ⎝⎝________⎠⎠" )
  fi
  if [[ $TIER == A ]]; then
    if [[ $1 == 0 ]]; then
      SPCOMP_PLAIN=( "  (( zZ ))" " (( (-.-) ))" "  ((______))" )
    else
      SPCOMP_PLAIN=( "  ((  zZ  ))" " ((  (-.-)  ))" "  ((________))" )
    fi
  fi
  SPCOMP_COL=()
  local w=0 l
  for l in "${SPCOMP_PLAIN[@]}"; do (( ${#l} > w )) && w=${#l}; done
  local i
  for i in "${!SPCOMP_PLAIN[@]}"; do
    SPCOMP_PLAIN[i]+=$(repeat_str " " $(( w - ${#SPCOMP_PLAIN[i]} )))
    SPCOMP_COL+=("${C_ICE}${SPCOMP_PLAIN[i]}${RS}")
  done
}

egg_frame() { # $1 = tilt: -1 0 1 2(crack)  $2 tint
  local tint=$2
  case $1 in
    -1) SPCOMP_PLAIN=( "  .-."  " ( ${G_SPARK} )" "  \`-'" ) ;;
     1) SPCOMP_PLAIN=( "  .-."  " ( ${G_SPARK} )" "  \`-." ) ;;
     2) SPCOMP_PLAIN=( "  .-."  " ( ${G_SPARK}\\)" "  \`-'" ) ;;
     *) SPCOMP_PLAIN=( "  .-."  " ( ${G_SPARK} )" "  \`-'" ) ;;
  esac
  SPCOMP_COL=()
  local l
  for l in "${SPCOMP_PLAIN[@]}"; do SPCOMP_COL+=("${tint}${l}${RS}"); done
}

# face table (design.md §6.5). Priority: forced > energy override > mood.
# wisdom ≥ 60 → mouth becomes the spectacles bridge '-' (composable).
pick_face() { # mood_bucket energy sick sleeping eating blink wisdom
  local mood=$1 energy=$2 sick=$3 sleeping=$4 eating=$5 blink=$6 wisdom=$7 face
  if [[ $sick == 1 ]]; then face="x.x"
  elif [[ $eating == 1 ]]; then face=">u<"
  elif [[ $sleeping == 1 || $blink == 1 ]]; then face="-.-"
  elif (( energy < 25 )); then face="¬.¬"; [[ $TIER == A ]] && face="=.="
  else
    case $mood in
      ecstatic)  face="^‿^" ;;
      content)   face="o‿o" ;;
      grumpy)    face="ò~ó"; [[ $TIER == A ]] && face=">_<" ;;
      miserable) face=";_;" ;;
      *)         face="o.o" ;;
    esac
    [[ $TIER == A && $face == *‿* ]] && face=${face//‿/u}
  fi
  # spectacles: earned at wisdom ≥ 60; not over forced sick/eat faces
  if (( wisdom >= 60 )) && [[ $sick != 1 && $eating != 1 ]]; then
    face="${face:0:1}-${face:2:1}"
  fi
  printf '%s' "$face"
}
