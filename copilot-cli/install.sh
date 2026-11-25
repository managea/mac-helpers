#!/bin/zsh
# Installs the Copilot CLI status tools for this user, by copying: the hook into the CLI's hooks folder, the
# supervised-builder agent into its agents folder (both under $COPILOT_HOME when set, else ~/.copilot), cpstatus,
# cpchat, cpsig, notify-done and cplog into ~/bin (or the folder given). Needs zsh and jq on PATH. The hook starts ~/bin/cpsig: with
# another folder, set AGENT_STATUS_NOTIFY to its cpsig in the CLI's environment.
#   install.sh [BIN]          copy, and say what was copied
#   install.sh --check [BIN]  copy nothing; say for each file whether the installed copy is the same
# The CLI loads hooks and agents when it starts: start it again afterwards. Nothing here uses the network.
here=${0:A:h}
check=0
[[ $1 == --check ]] && { check=1; shift; }
bin=${1:-$HOME/bin}
home=${COPILOT_HOME:-$HOME/.copilot}
names=(agent-status.sh agent-status.json supervised-builder.agent.md cpstatus cpchat cpsig notify-done cplog)
dests=($home/hooks $home/hooks $home/agents $bin $bin $bin $bin $bin)
modes=(755 644 644 755 755 755 755 755)
differ=0
for i in {1..${#names}}; do
  name=$names[i] dest=$dests[i] mode=$modes[i]
  if (( check )); then
    if cmp -s $here/$name $dest/$name; then print "same     $dest/$name"
    elif [[ -e $dest/$name ]]; then print "differs  $dest/$name"; differ=1
    else print "missing  $dest/$name"; differ=1; fi
  else
    mkdir -p $dest && install -m $mode $here/$name $dest/$name || { print -u2 "install.sh: could not copy $name"; exit 1; }
    print "copied   $dest/$name"
  fi
done
(( check )) && exit $differ
[[ :$PATH: == *:$bin:* ]] || print "note: $bin is not on PATH"
command -v jq >/dev/null || print "note: jq is not on PATH; the tools need it"
print "Start the Copilot CLI again to load the hook and the agent (/env lists them)."
