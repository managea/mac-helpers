#!/bin/zsh
# Copilot CLI hook: one line per session event in the CLI folder's agent-status.log, for whoever watches several sessions:
#   HH:MM:SS  NAME  STATE  detail
# Called as `agent-status.sh EVENT` with the hook's JSON on stdin (agent-status.json). It never writes prompt, reply
# or tool text, takes about 0.02 s and always exits 0, so a failure here never stops a session.
# The CLI's folder is $COPILOT_HOME when set, else ~/.copilot. Tools are found on PATH, with the system folders added
# for a hook started with a short one.
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

# A state repeated for the same session (agentStop and agent_completed both mean DONE) is written once.
mkdir -p $dir 2>/dev/null
last=$(tail -n 200 $log 2>/dev/null | N=$name awk '$2 == ENVIRON["N"] { s = $3 } END { print s }')
[[ $last == $state ]] && exit 0
{ print -r -- "$(date +%H:%M:%S)  $name  $state  $detail" >> $log } 2>/dev/null
exit 0
