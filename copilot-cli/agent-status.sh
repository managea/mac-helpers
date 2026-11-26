#!/bin/zsh
# Copilot CLI hook: one line per session event in the CLI folder's agent-status.log, for whoever watches several sessions:
#   HH:MM:SS  NAME  STATE  detail
# Called as `agent-status.sh EVENT` with the hook's JSON on stdin (agent-status.json). It never writes prompt, reply
# or tool text, takes about 0.02 s and always exits 0, so a failure here never stops a session. A new DONE, QUESTION,
# NEEDS-PERMISSION, ERROR, PLAN-READY, WAITING, WAITING-REVIEW, REVIEW-PASS or STOP line also starts ~/bin/cpsig NAME STATE (a desktop notification) in the background, when it
# is there; AGENT_STATUS_NOTIFY names another program, or turns that off when set but empty.
# The CLI's folder is $COPILOT_HOME when set, else ~/.copilot. Tools are found on PATH, with the system folders added
# for a hook started with a short one, and zsh's own options hold, whatever ~/.zshenv sets (nounset, say). Nothing it
# runs writes to stderr.
emulate -R zsh
PATH=$PATH:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin
event=${1:-unknown}
dir=${COPILOT_HOME:-$HOME/.copilot}
log=$dir/agent-status.log
payload=$(cat 2>/dev/null)

# The session id and, for a notification, its type; "-" stands for a missing one (read would drop an empty field).
fields=$(print -r -- "$payload" | jq -r 'def s(f): (f | if type == "string" and length > 0 then . else "-" end);
  [s(.sessionId // .session_id), s(.notification_type)] | @tsv' 2>/dev/null)
IFS=$'\t' read -r sid notice <<< "$fields"

case $event in
  sessionStart) state=STARTED ;;
  userPromptSubmitted) state=RUNNING ;;
  agentStop) state=DONE ;;
  preCompact) state=CONTEXT-80 ;;
  errorOccurred) state=ERROR ;;
  sessionEnd) state=ENDED ;;
  notification)
    case $notice in
      permission_prompt) state=NEEDS-PERMISSION ;;
      elicitation_dialog) state=QUESTION ;;
      agent_idle) state=IDLE ;;
      agent_completed) state=DONE ;;
    esac ;;
esac
[[ -n $state && -n $sid && $sid != - ]] || exit 0
detail=$event
[[ $event == notification ]] && detail=$notice

# The session's name from its workspace.yaml (only for an id that is safe in a path), else the first 8 characters of
# the id. Printable ASCII with spaces as underscores, at most 40 characters, so that every line splits on whitespace.
safe=$(print -r -- "$sid" | LC_ALL=C tr -cd 'A-Za-z0-9_-')
name=
yaml=$dir/session-state/$sid/workspace.yaml
if [[ $safe == $sid && -r $yaml ]]; then
  name=$(sed -n '/^name:/{s/^name:[[:space:]]*//;s/[[:space:]]*$//;p;q;}' $yaml 2>/dev/null)
  name=${name#[\"\']}
  name=${name%[\"\']}
fi
name=$(print -r -- "$name" | LC_ALL=C tr -cd '[:print:]' | tr ' ' _)
name=${name[1,40]}
[[ -n $name && $name != null ]] || name=${safe[1,8]}
[[ -n $name ]] || exit 0

# One run at a time for a session: agentStop and agent_completed come together, and two runs that both read the log
# before either writes would both write and both notify. The lock is a kernel lock (fcntl) on .agent-status.lock in the
# session's folder (else on one in the CLI's folder, for every session without a folder), waited for up to 2 s; then,
# or when it cannot be taken at all, the run goes on without it. It ends with the run that holds it, also with one that
# was stopped, so nothing is left behind and nothing is taken over. (A .agent-status-lock folder, which an earlier
# version locked with, means nothing.)
mkdir -p $dir 2>/dev/null
lock=$dir/.agent-status.lock
[[ $safe == $sid && -d $dir/session-state/$sid ]] && lock=$dir/session-state/$sid/.agent-status.lock
if zmodload zsh/system 2>/dev/null; then
  [[ -e $lock || -L $lock ]] || { : >> $lock } 2>/dev/null
  zsystem flock -t 2 -i 0.05 $lock 2>/dev/null
fi

# A turn that ends says DONE, unless the session keeps a status file that says otherwise: NAME.status, one line, in a
# runs folder of the session's folder or up to two folders below it (runs, */runs, */*/runs), or in a folder of
# $AGENT_STATUS_RUNS (separated by colons). Only its first words are taken, as one of the states below, and only when it
# was written in this turn: a prompt leaves a mark in the session's own folder, and an older file says nothing. A name
# with a / has none: NAME.status would be a path that leads out of the runs folders. When the mark or the kept state
# (below) is a symlink, neither is written through or read: the turn then says DONE.
turn=$dir/session-state/$sid/.agent-status-turn
saved=$dir/session-state/$sid/.agent-status-state
mark=0
[[ $safe == $sid && -d ${turn:h} && ! -L $turn && ! -L $saved ]] && mark=1
if (( mark )) && [[ $state == RUNNING ]]; then { : > $turn; : > $saved } 2>/dev/null; fi
# agentStop and agent_completed both end a turn, and the notification names no folder (workspace.yaml's is taken). An
# event that names its own folder, or that found a status file, keeps its state in .agent-status-state (the mark keeps
# the prompt's time), and for 5 s the other event says the same; but an agentStop with its own folder looks again when
# the kept state is DONE. After 5 s an end of the same turn looks again (the agent went on after a question, say), at
# the status files written since the prompt.
own= kept= recent=()
if (( mark )) && [[ $state == DONE ]]; then
  own=$(print -r -- "$payload" | jq -r '.cwd // empty | strings' 2>/dev/null)
  recent=($saved(N.ms-5))
fi
(( $#recent )) && { read -r kept < $saved } 2>/dev/null
if [[ $kept == (PLAN-READY|WAITING|WAITING-REVIEW|REVIEW-PASS|STOP) || ( $kept == DONE && -z $own ) ]]; then
  state=$kept
elif (( mark )) && [[ $state == DONE && -f $turn && $name != */* ]]; then
  cwd=$own
  [[ -n $cwd ]] || cwd=$(sed -n '/^cwd:/{s/^cwd:[[:space:]]*//;s/[[:space:]]*$//;p;q;}' $yaml 2>/dev/null)
  files=()
  for runs in ${(s.:.)AGENT_STATUS_RUNS-}; do files+=($runs/$name.status); done
  # In the session's folder only folders are tried, smallest first, at most 2,000 at each level, and about 10,000
  # entries are read in all: a folder's size says how many it holds without reading it (APFS gives 32 bytes an entry).
  # So a folder with many entries never slows a turn; a glob such as $cwd/*/*/runs opens every entry two levels down.
  if [[ $cwd == /* ]]; then
    zmodload -F zsh/stat b:zstat 2>/dev/null
    files+=($cwd/runs/$name.status)
    budget=320000 left=2000 outer=()
    zstat -A size +size -- $cwd 2>/dev/null && (( size[1] <= budget )) &&
      { outer=($cwd/*(N-/oLY$left)); (( budget -= size[1] )) }
    files+=(${^outer}/runs/$name.status)
    for d in $outer; do
      (( left > 0 )) || break
      zstat -A size +size -- $d 2>/dev/null && (( size[1] <= budget )) || continue
      inner=($d/*(N-/oLY$left))
      files+=(${^inner}/runs/$name.status)
      (( budget -= size[1], left -= $#inner ))
    done
  fi
  for file in $files; do
    [[ -f $file && $file -nt $turn ]] || continue
    said=$(head -c 200 $file 2>/dev/null | head -n 1 | LC_ALL=C tr '[:lower:]' '[:upper:]' 2>/dev/null |
      LC_ALL=C tr -s ' \t_' '-' 2>/dev/null)
    case $said in
      PLAN-READY*) state=PLAN-READY ;;
      WAITING-REVIEW*) state=WAITING-REVIEW ;;
      WAITING*) state=WAITING ;;
      REVIEW-PASS*) state=REVIEW-PASS ;;
      STOP*) state=STOP ;;
    esac
    break
  done
  [[ -n $own || $state != DONE ]] && { print -r -- $state > $saved } 2>/dev/null
fi

# A state repeated for the same session (agentStop and agent_completed both mean DONE) is written once.
last=$(tail -n 200 $log 2>/dev/null | N=$name awk '$2 == ENVIRON["N"] { s = $3 } END { print s }')
[[ $last == $state ]] && exit 0
if { print -r -- "$(date +%H:%M:%S)  $name  $state  $detail" >> $log } 2>/dev/null; then
  # A state that wants someone's attention: a notification, started in the background so the session never waits.
  notify=${AGENT_STATUS_NOTIFY-$HOME/bin/cpsig}
  case $state in
    DONE|QUESTION|NEEDS-PERMISSION|ERROR|PLAN-READY|WAITING|WAITING-REVIEW|REVIEW-PASS|STOP)
      [[ -n $notify && -x $notify ]] && "$notify" "$name" "$state" </dev/null >/dev/null 2>&1 & ;;
  esac
fi
exit 0
