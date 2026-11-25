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
# A stand-in for cpsig, so no real notification shows: each call the hook starts adds a "NAME STATE" line. The hook
# starts it in the background, so settle N waits until N lines are there (5 s at most).
notified=$tmp/notified
print -r -- "#!/bin/zsh
print -r -- \"\$1 \$2\" >> $notified" > $tmp/notify && chmod 755 $tmp/notify
export AGENT_STATUS_NOTIFY=$tmp/notify
settle() { local i; for i in {1..50}; do (( $(cat $notified 2>/dev/null | wc -l) >= $1 )) && break; sleep 0.1; done; sleep 0.2; }

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
# A notification for each new state that wants attention, none for the rest or for the repeated DONE.
settle 4
check notified "$(LC_ALL=C sort $notified)" "Build_API DONE
Build_API QUESTION
a-very-long-session-name-that-goes-past- NEEDS-PERMISSION
cccc3333 ERROR"
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
8 copied
1 note:"
check "install check" "$(zsh $tools/install.sh --check $bin | /usr/bin/awk '{ print $1 }' | sort | uniq -c | /usr/bin/awk '{ print $1, $2 }'; print $?)" "8 same
0"
[[ -x $bin/cpchat && -x $bin/cpsig && -x $bin/notify-done && -x $bin/cplog && -x $HOME/.copilot/hooks/agent-status.sh ]] || { print -u2 "FAIL install modes"; fails=$((fails + 1)); }
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

# Notifications: the run with HOME moved (its log folder is created, so it writes) and the COPILOT_HOME run above added
# one each (6 in all); none when AGENT_STATUS_NOTIFY is set but empty, and a missing program changes nothing (the hook
# still exits 0). The empty-PATH run had no AGENT_STATUS_NOTIFY and no ~/bin/cpsig, so it started nothing.
settle 6
check "notify count" "$(wc -l < $notified | /usr/bin/tr -d ' ')" 6
check "notify off" "$(AGENT_STATUS_NOTIFY= hook agentStop "{\"sessionId\":\"$s3\"}")" 0
check "notify missing" "$(AGENT_STATUS_NOTIFY=$tmp/none hook errorOccurred "{\"sessionId\":\"$s2\"}")" 0
sleep 0.5
check "notify none" "$(wc -l < $notified | /usr/bin/tr -d ' ')" 6

# cpsig: osascript gets the name and state as arguments after --, so quotes in a name stay text; without osascript
# on PATH it does nothing. A stand-in osascript records its arguments; no real notification shows.
mkdir -p $tmp/fakebin $tmp/nobin
print -r -- "#!/bin/zsh
print -r -- \"\$@\" > $tmp/osa-args" > $tmp/fakebin/osascript && chmod 755 $tmp/fakebin/osascript
check "cpsig exit" "$(PATH=$tmp/fakebin:/usr/bin:/bin /bin/zsh -f $tools/cpsig 'say "hi" & x' DONE; print $?)" 0
args=$(<$tmp/osa-args)
check "cpsig args" "${args##* -- }" 'say "hi" & x DONE'
check "cpsig title" "$(print -r -- $args | /usr/bin/grep -c 'with title "CPSIG"')" 1
check "cpsig no osascript" "$(PATH=$tmp/nobin /bin/zsh -f $tools/cpsig a b 2>&1; print $?)" 0

# The status file: what it says in place of DONE, only when written in this turn, only for the session's own name.
sp=dddd4444-0000-4000-8000-000000000004
pr=$tmp/ws
mkdir -p $HOME/.copilot/session-state/$sp $pr/notes/wip/runs $pr/runs $tmp/elsewhere
printf 'id: %s\ncwd: %s\nname: wp3-build\n' $sp $pr > $HOME/.copilot/session-state/$sp/workspace.yaml
export AGENT_STATUS_NOTIFY=$tmp/notify3 && print -r -- "#!/bin/zsh
print -r -- \"\$1 \$2\" >> $tmp/notified3" > $tmp/notify3 && chmod 755 $tmp/notify3
turn() { hook userPromptSubmitted "{\"sessionId\":\"$sp\"}" >/dev/null; sleep 0.05; }
ends() { hook agentStop "{\"sessionId\":\"$sp\",\"cwd\":\"$pr\"}" >/dev/null; hook notification "{\"sessionId\":\"$sp\",\"notification_type\":\"agent_completed\"}" >/dev/null; }
last() { lines | /usr/bin/grep '^wp3-build ' | tail -1 | /usr/bin/awk '{ print $2 }'; }
f=$pr/notes/wip/runs/wp3-build.status
said() { turn; print -r -- "$1" > $f; ends; last; }
check "plan ready" "$(said 'PLAN READY')" PLAN-READY
check "plan ready once" "$(lines | /usr/bin/grep -c '^wp3-build  PLAN-READY')" 1
check "waiting review" "$(said 'waiting review: round 2')" WAITING-REVIEW
check "waiting" "$(said 'WAITING which table holds it?')" WAITING
check "no text written" "$(/usr/bin/grep -c 'table' $log)" 0
check "review pass" "$(said 'REVIEW PASS')" REVIEW-PASS
check "stop" "$(said 'STOP')" STOP
check "done" "$(said 'DONE')" DONE
check "running" "$(said 'RUNNING')" DONE
check "other words" "$(said 'planning something')" DONE
print 'PLAN READY' > $f; sleep 0.05; turn; ends
check "an older file says nothing" "$(last)" DONE
rm $f; turn; print 'PLAN READY' > $pr/notes/wip/runs/other.status; ends
check "another session's file" "$(last)" DONE
turn; print 'PLAN READY' > $tmp/elsewhere/wp3-build.status; ends
check "a folder it does not look in" "$(last)" DONE
turn; print 'PLAN READY' > $tmp/elsewhere/wp3-build.status; export AGENT_STATUS_RUNS=/nowhere:$tmp/elsewhere; ends; unset AGENT_STATUS_RUNS
check "AGENT_STATUS_RUNS" "$(last)" PLAN-READY
turn; print 'STOP' > $pr/runs/wp3-build.status; hook agentStop "{\"sessionId\":\"$sp\"}" >/dev/null
check "the folder from workspace.yaml" "$(last)" STOP
turn; mkdir $pr/notes/wip/runs/wp3-build.status; rm $pr/runs/wp3-build.status; ends
check "a folder of that name" "$(last)" DONE
# agentStop names another folder than workspace.yaml, and agent_completed none: whichever comes first decides, the
# other says the same, and the turn is logged once.
mkdir -p $tmp/ws2/runs
stop2() { hook agentStop "{\"sessionId\":\"$sp\",\"cwd\":\"$tmp/ws2\"}" >/dev/null; }
completed() { hook notification "{\"sessionId\":\"$sp\",\"notification_type\":\"agent_completed\"}" >/dev/null; }
two() { lines | /usr/bin/grep '^wp3-build ' | tail -2 | /usr/bin/awk '{ print $2 }' | /usr/bin/tr '\n' ' '; }
turn; print 'PLAN READY' > $tmp/ws2/runs/wp3-build.status; stop2; completed
check "one decision" "$(two)" "RUNNING PLAN-READY "
turn; print 'PLAN READY' > $tmp/ws2/runs/wp3-build.status; completed; stop2
check "one decision, the other way round" "$(two)" "RUNNING DONE "
rm $tmp/ws2/runs/wp3-build.status
for i in {1..50}; do (( $(/usr/bin/grep -c . $tmp/notified3 2>/dev/null) >= 12 )) && break; sleep 0.1; done
check "notified" "$(sort -u $tmp/notified3 | tr '\n' ',')" "wp3-build DONE,wp3-build PLAN-READY,wp3-build REVIEW-PASS,wp3-build STOP,wp3-build WAITING,wp3-build WAITING-REVIEW,"

# Folders with many entries: folders only, smallest first, at most 2,000 at each level, about 10,000 entries read.
# In c, aaa (2,100 folders) takes the 2,000 before zzz (2,100 files and x) is read; notes, the smallest, comes first.
# In b, data (10,500 files and x) is past what is read; b/data as the session's folder is not read either.
sb=eeee5555-0000-4000-8000-000000000005
bw=$tmp/bw
mkdir -p $HOME/.copilot/session-state/$sb $bw/c/aaa/d{1..2100} $bw/{b,c}/notes/wip/runs $bw/c/zzz/x/runs \
  $bw/b/data/{x,}/runs
: > $bw/c/zzz/f{1..2100}
: > $bw/b/data/f{1..10500}
printf 'id: %s\ncwd: %s\nname: big\n' $sb $bw/c > $HOME/.copilot/session-state/$sb/workspace.yaml
big() { # big FOLDER FILE STATE: what a turn in FOLDER says when FILE (below it) says STATE
  hook userPromptSubmitted "{\"sessionId\":\"$sb\"}" >/dev/null; sleep 0.05; print -r -- $3 > $bw/$1/$2
  hook agentStop "{\"sessionId\":\"$sb\",\"cwd\":\"$bw/$1\"}" >/dev/null; rm $bw/$1/$2
  lines | /usr/bin/grep '^big ' | tail -1 | /usr/bin/awk '{ print $2 }'
}
check "smallest first" "$(big c notes/wip/runs/big.status 'PLAN READY')" PLAN-READY
check "2,000 two levels down" "$(big c zzz/x/runs/big.status STOP)" DONE
check "many entries, beside" "$(big b notes/wip/runs/big.status WAITING)" WAITING
check "many entries, not read" "$(big b data/x/runs/big.status STOP)" DONE
check "many entries, its runs" "$(big b/data runs/big.status 'REVIEW PASS')" REVIEW-PASS
check "many entries, below it" "$(big b/data x/runs/big.status STOP)" DONE

# Two runs at once for one session (agentStop and agent_completed come together): one line and one notification, for
# sessions with a folder in session-state and without. A lock left by a stopped run is taken over, a live one waited for.
print -r -- "#!/bin/zsh
print -r -- \"\$1 \$2\" >> $tmp/notified4" > $tmp/notify4 && chmod 755 $tmp/notify4
export AGENT_STATUS_NOTIFY=$tmp/notify4
for k in {10..21}; do
  id=ffff00$k-0000-4000-8000-0000000000$k
  (( k < 16 )) && mkdir -p $HOME/.copilot/session-state/$id
  hook agentStop "{\"sessionId\":\"$id\"}" >/dev/null &
  hook notification "{\"sessionId\":\"$id\",\"notification_type\":\"agent_completed\"}" >/dev/null &
  wait
done
check "at once" "$(lines | /usr/bin/grep -c '^ffff00[12][0-9]  DONE')" 12
for i in {1..50}; do (( $(/usr/bin/grep -c . $tmp/notified4 2>/dev/null) >= 12 )) && break; sleep 0.1; done; sleep 0.3
check "at once, notified" "$(/usr/bin/grep -c DONE $tmp/notified4)" 12
lk=$HOME/.copilot/session-state/ffff0030-0000-4000-8000-000000000030/.agent-status-lock
mkdir -p $lk && touch -t 202001010000 $lk
hook errorOccurred '{"sessionId":"ffff0030-0000-4000-8000-000000000030"}' >/dev/null
check "a stale lock" "$(lines | tail -1)$([[ -e $lk ]] && print ' (still there)')" "ffff0030  ERROR  errorOccurred"
lk=$HOME/.copilot/session-state/ffff0031-0000-4000-8000-000000000031/.agent-status-lock
mkdir -p $lk
hook errorOccurred '{"sessionId":"ffff0031-0000-4000-8000-000000000031"}' >/dev/null & hp=$!
sleep 0.4; before=$(lines | /usr/bin/grep -c '^ffff0031 '); rmdir $lk; wait $hp
check "a live lock" "$before $(lines | /usr/bin/grep -c '^ffff0031 ')" "0 1"
locks=($HOME/.copilot/session-state/*/.agent-status-lock(N) $HOME/.copilot/.agent-status-lock-*(N))
check "no lock left" "$locks" ""

# A name with / has no status file: NAME.status would lead out of the runs folders.
sl=ffff0040-0000-4000-8000-000000000040
mkdir -p $HOME/.copilot/session-state/$sl $tmp/sl/p/runs/feature $tmp/sl/outside
slash() { # slash NAME FILE: what a turn says when FILE says STOP
  printf 'id: %s\ncwd: %s\nname: %s\n' $sl $tmp/sl/p "$1" > $HOME/.copilot/session-state/$sl/workspace.yaml
  hook userPromptSubmitted "{\"sessionId\":\"$sl\"}" >/dev/null; sleep 0.05; print STOP > $2
  hook agentStop "{\"sessionId\":\"$sl\"}" >/dev/null; rm $2
  lines | tail -1 | /usr/bin/awk '{ print $1, $2 }'
}
check "a name with /" "$(slash feature/login $tmp/sl/p/runs/feature/login.status)" "feature/login DONE"
check "a name with ../" "$(slash ../../outside/x $tmp/sl/outside/x.status)" "../../outside/x DONE"

# Nothing on stderr and exit 0: a status file with bytes that are not UTF-8 in a UTF-8 locale, a session folder the
# turn's mark cannot be written in, and options that ~/.zshenv sets, in a folder with a space.
so=ffff0050-0000-4000-8000-000000000050
sr=ffff0051-0000-4000-8000-000000000051
sw="$tmp/so ws"
mkdir -p $HOME/.copilot/session-state/{$so,$sr} "$sw/notes/wip/runs" $tmp/zd
printf 'id: %s\ncwd: %s\nname: opts\n' $so "$sw" > $HOME/.copilot/session-state/$so/workspace.yaml
print 'setopt nounset errexit ksharrays shwordsplit globsubst noclobber globdots' > $tmp/zd/.zshenv
quiet() { # quiet EVENT [SESSION [ZDOTDIR]]: what the hook writes to stdout and stderr, then its exit code
  print -r -- "{\"sessionId\":\"${2:-$so}\"}" | LC_ALL=en_US.UTF-8 ZDOTDIR=${3:-$tmp/none} zsh $tools/agent-status.sh $1 2>&1
  print -n "$? "
}
opts() { lines | /usr/bin/grep '^opts ' | tail -2 | /usr/bin/awk '{ print $2 }' | /usr/bin/tr '\n' ' '; }
out=$(quiet userPromptSubmitted; sleep 0.05; printf 'waiting: caf\xe9 table\n' > "$sw/notes/wip/runs/opts.status"
  quiet agentStop)
check "not UTF-8" "$out$(opts)" "0 0 RUNNING WAITING "
chmod 555 $HOME/.copilot/session-state/$sr
check "a mark that cannot be written" "$(quiet userPromptSubmitted $sr)" "0 "
chmod 755 $HOME/.copilot/session-state/$sr
out=$(quiet userPromptSubmitted $so $tmp/zd; sleep 0.05; print 'PLAN READY' > "$sw/notes/wip/runs/opts.status"
  quiet agentStop $so $tmp/zd; quiet somethingElse $so $tmp/zd)
check "options" "$out$(opts)" "0 0 0 RUNNING PLAN-READY "

# notify-done: the command's output and exit code kept, a line and a notification for each way it can end.
mine=$tmp/notified2
print -r -- "#!/bin/zsh
print -r -- \"\$1 \$2\" >> $mine" > $tmp/notify2 && chmod 755 $tmp/notify2
nd() { AGENT_STATUS_NOTIFY=$tmp/notify2 COPILOT_HOME=$tmp/nd zsh $tools/notify-done "$@"; print "code $?"; }
check "nd ok" "$(nd ok print -r -- 'a  b' 2>&1)" "a  b
notify-done ok: EXIT 0
code 0"
check "nd fails" "$(nd bad zsh -c 'print out; exit 3' 2>&1)" "out
notify-done bad: EXIT 3
code 3"
check "nd no command" "$(nd gone no-such-command-here 2>/dev/null)" "notify-done gone: EXIT 127
code 127"
check "nd ctrl-c" "$(nd stop zsh -c 'kill -INT $$' 2>/dev/null)" "notify-done stop: EXIT 130
code 130"
check "nd notified" "$(<$mine)" "ok DONE
bad FAILED
gone FAILED
stop FAILED"
check "nd log" "$(/usr/bin/sed -E 's/^[0-9]{2}:[0-9]{2}:[0-9]{2}  //' $tmp/nd/agent-status.log)" "ok  DONE  exit-0
bad  FAILED  exit-3
gone  FAILED  exit-127
stop  FAILED  exit-130"
for bad in "" "two words" 'a;b' "$(printf 'x%.0s' {1..41})"; do
  check "nd name ${bad[1,9]}" "$(nd "$bad" print never 2>/dev/null)" "code 2"
done
check "nd no arguments" "$(nd only 2>/dev/null)" "code 2"
check "nd nobody to tell" "$(AGENT_STATUS_NOTIFY= COPILOT_HOME=$tmp/nd2 zsh $tools/notify-done q true; print $?)" "notify-done q: EXIT 0
0"
# SIGTERM or SIGHUP sent to notify-done alone: passed on, so the command ends at once, and reported like Ctrl+C.
for sig code in TERM 143 HUP 129; do
  AGENT_STATUS_NOTIFY=$tmp/notify2 COPILOT_HOME=$tmp/nd zsh $tools/notify-done sig-$sig sleep 30 > $tmp/nd-$sig 2>&1 &
  ndpid=$! child=
  for i in {1..50}; do child=$(pgrep -P $ndpid sleep) && break; sleep 0.1; done
  kill -$sig $ndpid; wait $ndpid
  check "nd $sig" "$? $(<$tmp/nd-$sig)" "$code notify-done sig-$sig: EXIT $code"
  check "nd $sig ends the command" "${child:+started} $(kill -0 $child 2>/dev/null && print running || print ended)" \
    "started ended"
done
check "nd signals" "$(/usr/bin/sed -E 's/^[0-9:]{8}  //' $tmp/nd/agent-status.log | tail -2; tail -2 $mine)" \
  "sig-TERM  FAILED  exit-143
sig-HUP  FAILED  exit-129
sig-TERM FAILED
sig-HUP FAILED"

# cplog: the last lines, then what is added, until it is ended.
mkdir -p $tmp/cl && print -l one two three > $tmp/cl/agent-status.log
COPILOT_HOME=$tmp/cl zsh $tools/cplog 2 > $tmp/cl/out 2>/dev/null & clpid=$!
for i in {1..50}; do /usr/bin/grep -q three $tmp/cl/out && break; sleep 0.1; done
print four >> $tmp/cl/agent-status.log
for i in {1..50}; do /usr/bin/grep -q four $tmp/cl/out && break; sleep 0.1; done
kill $clpid 2>/dev/null; wait $clpid 2>/dev/null
check "cplog" "$(/usr/bin/grep -aoE '(one|two|three|four)' $tmp/cl/out)" "two
three
four"
check "cplog bad N" "$(zsh $tools/cplog x 2>&1 >/dev/null; print $?)" "usage: cplog [N]   (N: how many lines, 15)
2"

(( fails == 0 )) && print "copilot-cli OK" || { print -u2 "$fails failed"; exit 1; }
