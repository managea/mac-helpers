#!/bin/zsh
# The Copilot CLI status tools against sample hook payloads and session files in a temporary home folder.
# Needs zsh and jq. Neutral sample content only.
cd "${0:A:h}/.." || exit 1
tools=$PWD
export TZ=UTC
tmp=$(mktemp -d "${TMPDIR:-/tmp}/av-cli.XXXXXX")
export HOME=$tmp/home
mkdir -p $HOME/.copilot/session-state
trap 'rm -rf $tmp' EXIT
fails=0
check() { # check NAME ACTUAL EXPECTED
  if [[ $2 == $3 ]]; then return 0; fi
  print -u2 "FAIL $1"; print -u2 "  got:  ${(qqq)2}"; print -u2 "  want: ${(qqq)3}"; fails=$((fails + 1))
}
hook() { print -r -- "$2" | zsh $tools/agent-status.sh $1; print $?; }
log=$HOME/.copilot/agent-status.log
lines() { [[ -r $log ]] && /usr/bin/sed -E 's/^[0-9]{2}:[0-9]{2}:[0-9]{2}  //' $log; }

# Sessions: a named one in a project folder, one with a long name, one without a workspace.yaml.
s1=aaaa1111-0000-4000-8000-000000000001
s2=bbbb2222-0000-4000-8000-000000000002
s3=cccc3333-0000-4000-8000-000000000003
mkdir -p $HOME/.copilot/session-state/{$s1,$s2,$s3} $tmp/project
printf 'id: %s\ncwd: %s\nname: "Build API"  \n' $s1 $tmp/project > $HOME/.copilot/session-state/$s1/workspace.yaml
printf 'id: %s\ncwd: /elsewhere\nname: %s\n' $s2 "a-very-long-session-name-that-goes-past-forty-characters" \
  > $HOME/.copilot/session-state/$s2/workspace.yaml

# The hook: states, names, repeats, what is never written, and that it always exits 0.
check prompt "$(hook userPromptSubmitted "{\"sessionId\":\"$s1\",\"prompt\":\"private words here\",\"cwd\":\"/x\"}")" 0
check repeat "$(hook userPromptSubmitted "{\"sessionId\":\"$s1\",\"prompt\":\"again\"}")" 0
hook sessionStart "{\"sessionId\":\"$s1\",\"initialPrompt\":\"private words here\"}" >/dev/null
hook notification "{\"sessionId\":\"$s1\",\"notification_type\":\"elicitation_dialog\",\"message\":\"private words\"}" >/dev/null
hook notification "{\"sessionId\":\"$s1\",\"notification_type\":\"shell_completed\"}" >/dev/null
hook agentStop "{\"sessionId\":\"$s1\",\"stopReason\":\"end_turn\"}" >/dev/null
hook notification "{\"sessionId\":\"$s1\",\"notification_type\":\"agent_completed\"}" >/dev/null
hook notification "{\"sessionId\":\"$s2\",\"notification_type\":\"permission_prompt\"}" >/dev/null
hook preCompact "{\"sessionId\":\"$s3\"}" >/dev/null
hook errorOccurred "{\"session_id\":\"$s3\"}" >/dev/null
hook notification "{\"sessionId\":\"$s3\",\"notification_type\":\"agent_idle\"}" >/dev/null
hook sessionEnd "{\"sessionId\":\"$s3\"}" >/dev/null
check states "$(lines)" "Build_API  RUNNING  userPromptSubmitted
Build_API  STARTED  sessionStart
Build_API  QUESTION  elicitation_dialog
Build_API  DONE  agentStop
a-very-long-session-name-that-goes-past-  NEEDS-PERMISSION  permission_prompt
cccc3333  CONTEXT-80  preCompact
cccc3333  ERROR  errorOccurred
cccc3333  IDLE  agent_idle
cccc3333  ENDED  sessionEnd"
check "time shape" "$(/usr/bin/grep -cvE '^[0-9]{2}:[0-9]{2}:[0-9]{2}  [^ ]+  [A-Z0-9-]+  [a-z_A-Z]+$' $log)" 0
check "no prompt text" "$(/usr/bin/grep -c private $log)" 0
before=$(wc -l < $log)
check "bad json" "$(hook userPromptSubmitted 'not json')" 0
check "no session id" "$(hook userPromptSubmitted '{"prompt":"x"}')" 0
check "unknown event" "$(hook somethingElse "{\"sessionId\":\"$s1\"}")" 0
check "nothing written" "$(wc -l < $log)" "$before"
# An id that is not safe in a path: no workspace.yaml is read through it, and the name comes from its safe characters.
hook userPromptSubmitted '{"sessionId":"../../outside"}' >/dev/null
check "unsafe id" "$(lines | tail -1)" "outside  RUNNING  userPromptSubmitted"
# Control characters and spaces in a name.
s4=dddd4444-0000-4000-8000-000000000004
mkdir -p $HOME/.copilot/session-state/$s4
printf "id: x\nname: 'tab\there \033[1mbold'\n" > $HOME/.copilot/session-state/$s4/workspace.yaml
hook userPromptSubmitted "{\"sessionId\":\"$s4\"}" >/dev/null
check "printable name" "$(lines | tail -1)" "tabhere_[1mbold  RUNNING  userPromptSubmitted"
# A home folder the hook cannot write to: still exit 0, nothing on stderr.
err=$(print -r -- "{\"sessionId\":\"$s1\"}" | HOME=$tmp/nofolder/file zsh $tools/agent-status.sh agentStop 2>&1; print "exit $?")
check "unwritable" "$err" "exit 0"

# cpstatus: newest session first, the latest state of each, lines it cannot read left out.
print "12:00:00,  legacy,  RUNNING,  userPromptSubmitted\nnot a status line" >> $log
st=$(zsh $tools/cpstatus | /usr/bin/awk '{ print $1, $2 }')
check cpstatus "$st" "tabhere_[1mbold RUNNING
outside RUNNING
cccc3333 ENDED
a-very-long-session-name-that-goes-past- NEEDS-PERMISSION
Build_API DONE"
check "cpstatus no log" "$(HOME=$tmp/empty zsh $tools/cpstatus 2>&1; print $?)" "cpstatus: no status log at $tmp/empty/.copilot/agent-status.log
1"

# cpchat: a session's main conversation.
ev=$HOME/.copilot/session-state/$s1/events.jsonl
long=$(printf 'w%.0s' {1..450})
{
  print -r -- '{"type":"session.start","timestamp":"2026-01-02T03:00:00.000Z","data":{}}'
  print -r -- '{"type":"user.message","timestamp":"2026-01-02T03:04:05.123Z","data":{"content":"Add a greeting\nwith a tab\there"}}'
  print -r -- '{"type":"tool.execution_start","timestamp":"2026-01-02T03:04:06Z","data":{"toolName":"bash","arguments":{"command":"ls"}}}'
  print -r -- '{"type":"assistant.message","timestamp":"2026-01-02T03:04:07Z","data":{"content":""}}'
  print -r -- '{"type":"assistant.message","timestamp":"2026-01-02T03:05:00Z","data":{"content":"Step one done"}}'
  print -r -- '{"type":"user.message","agentId":"sub-1","timestamp":"2026-01-02T03:05:01Z","data":{"content":"Review this diff"}}'
  print -r -- '{"type":"assistant.message","agentId":"sub-1","timestamp":"2026-01-02T03:05:02Z","data":{"content":"PASS"}}'
  print -r -- '{"type":"tool.execution_start","agentId":"sub-1","timestamp":"2026-01-02T03:05:02Z","data":{"toolName":"view"}}'
  print -r -- 'not json at all'
  print -r -- '{"type":"tool.execution_start","timestamp":"2026-01-02T03:06:00Z","data":{"toolName":"ask_user","arguments":{"message":"Which colour?","requestedSchema":{"properties":{"c":{"enum":["red","blue"]}}}}}}'
  print -r -- '{"type":"assistant.message","timestamp":"2026-01-02T03:07:00Z","data":{"content":"Step one done"}}'
  print -r -- '{"type":"assistant.message","timestamp":"2026-01-02T03:08:00Z","data":{"content":"Colour \u001b[31mred"}}'
  print -r -- "{\"type\":\"assistant.message\",\"timestamp\":\"2026-01-02T03:09:00Z\",\"data\":{\"content\":\"$long\"}}"
} > $ev
cut=$(printf 'w%.0s' {1..400})
check cpchat "$(zsh $tools/cpchat 'Build API')" "03:04 user: Add a greeting with a tab here
03:05 asst: Step one done
03:08 asst: Colour ?[31mred
03:09 asst: $cut..."
check "cpchat -a" "$(zsh $tools/cpchat Build_API 3 -a)" "03:05 asst: Step one done
03:06 question: Which colour? | choices: {\"properties\":{\"c\":{\"enum\":[\"red\",\"blue\"]}}}
03:08 asst: Colour ?[31mred
03:09 asst: $cut..."
check "cpchat -f" "$(zsh $tools/cpchat aaaa1111 1 -f)" "03:09 asst: $long"
check "cpchat cwd" "$(cd $tmp/project && zsh $tools/cpchat . 1)" "03:09 asst: $cut..."
check "cpchat no session" "$(zsh $tools/cpchat nobody 2>&1; print $?)" "cpchat: no session nobody
1"
print '{"type":"tool.execution_start","data":{"toolName":"bash"}}' > $HOME/.copilot/session-state/$s3/events.jsonl
check "cpchat no messages" "$(zsh $tools/cpchat cccc3333 2>&1; print $?)" \
  "cpchat: no messages parsed in $HOME/.copilot/session-state/$s3/events.jsonl (format changed?)
1"
check "cpchat bad N" "$(zsh $tools/cpchat Build_API x 2>&1; print $?)" "cpchat: N must be a whole number above 0
2"

# install.sh: copies, then --check finds them the same.
bin=$tmp/bin
out=$(zsh $tools/install.sh $bin)
check install "$(print -r -- $out | /usr/bin/awk '{ print $1 }' | sort | uniq -c | /usr/bin/awk '{ print $1, $2 }')" "1 Start
5 copied
1 note:"
check "install check" "$(zsh $tools/install.sh --check $bin | /usr/bin/awk '{ print $1 }' | sort | uniq -c | /usr/bin/awk '{ print $1, $2 }'; print $?)" "5 same
0"
[[ -x $bin/cpchat && -x $HOME/.copilot/hooks/agent-status.sh ]] || { print -u2 "FAIL install modes"; fails=$((fails + 1)); }
print changed >> $bin/cpstatus
check "install check differs" "$(zsh $tools/install.sh --check $bin | /usr/bin/grep -c differs; print ${pipestatus[1]})" "1
1"

# COPILOT_HOME moves everything: the hook writes there, cpstatus and cpchat read there, install.sh copies there, and
# the hook config's command, run by bash as the CLI runs it, reaches the installed hook.
alt=$tmp/alt\ home
mkdir -p "$alt/session-state/$s1"
cp $HOME/.copilot/session-state/$s1/* "$alt/session-state/$s1/"
print -r -- "{\"sessionId\":\"$s1\"}" | COPILOT_HOME=$alt zsh $tools/agent-status.sh agentStop
check "alt log" "$(/usr/bin/sed -E 's/^[0-9:]{8}  //' "$alt/agent-status.log")" "Build_API  DONE  agentStop"
check "alt cpstatus" "$(COPILOT_HOME=$alt zsh $tools/cpstatus | /usr/bin/awk '{ print $1, $2 }')" "Build_API DONE"
check "alt cpchat" "$(COPILOT_HOME=$alt zsh $tools/cpchat Build_API 1)" "03:09 asst: $cut..."
COPILOT_HOME=$alt zsh $tools/install.sh $tmp/bin2 >/dev/null
check "alt install" "$(ls "$alt/hooks" "$alt/agents" | /usr/bin/tr '\n' ' ')" "$alt/agents: supervised-builder.agent.md  $alt/hooks: agent-status.json agent-status.sh "
command=$(/usr/bin/jq -r '.hooks.sessionStart[0].bash' $tools/agent-status.json)
print -r -- "{\"sessionId\":\"$s1\"}" | COPILOT_HOME=$alt /bin/bash -c "$command"
check "hook command" "$(/usr/bin/tail -1 "$alt/agent-status.log" | /usr/bin/sed -E 's/^[0-9:]{8}  //')" "Build_API  STARTED  sessionStart"
# A hook started with an empty PATH still finds its tools.
print -r -- "{\"sessionId\":\"$s1\"}" | /usr/bin/env -i HOME=$HOME /bin/zsh -f $tools/agent-status.sh errorOccurred
check "empty PATH" "$(lines | tail -1)" "Build_API  ERROR  errorOccurred"

(( fails == 0 )) && print "copilot-cli OK" || { print -u2 "$fails failed"; exit 1; }
