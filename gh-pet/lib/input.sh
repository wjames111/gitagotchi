# gitagotchi — lib/input.sh
# read -rsn1 with escape-sequence decoding for arrows (plan.md §8.2).
# read's timeout doubles as the 4 fps frame clock.
#
# read_key sets KEY (no subshell — one fork saved per tick, and a lone ESC
# chased by a fast keypress stashes that key in KEY_PENDING for the next
# tick instead of swallowing it).

KEY="" KEY_PENDING=""

read_key() { # $1 = timeout → KEY: char | up|down|left|right | esc | enter | backtab | ""
  KEY=""
  if [[ -n $KEY_PENDING ]]; then
    KEY=$KEY_PENDING KEY_PENDING=""
    return 0
  fi
  local k b1 b2
  IFS= read -rsn1 -t "$1" k 2>/dev/null || return 0
  if [[ $k == $'\e' ]]; then
    if ! IFS= read -rsn1 -t 0.01 b1 2>/dev/null; then KEY=esc; return 0; fi
    if [[ $b1 == '[' || $b1 == O ]]; then
      IFS= read -rsn1 -t 0.01 b2 2>/dev/null || b2=""
      case $b2 in
        A) KEY=up ;; B) KEY=down ;; C) KEY=right ;; D) KEY=left ;;
        Z) KEY=backtab ;;
        *) KEY=esc ;;
      esac
    else
      # ESC chased by another key — deliver esc now, the key next tick
      # (stash TOKENS: a raw \e or newline byte would match no handler)
      KEY=esc
      if [[ $b1 == $'\e' ]]; then KEY_PENDING=esc
      elif [[ -n $b1 ]]; then KEY_PENDING=$b1
      else KEY_PENDING=enter; fi
    fi
  elif [[ -z $k ]]; then
    KEY=enter          # read returns empty string on newline
  else
    KEY=$k
  fi
  return 0
}

open_url() { # best effort, silent
  [[ -z $1 ]] && return
  if have open; then open "$1" >/dev/null 2>&1 &
  elif have xdg-open; then xdg-open "$1" >/dev/null 2>&1 &
  fi
}
