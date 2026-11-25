# Copilot CLI status tools

Small tools for anyone running several GitHub Copilot CLI sessions at once and keeping an eye on them:
a status log that every session writes to, a desktop notification when a session wants attention or a command started
by hand has ended, a one-line overview per session, a session's conversation as text, and a custom agent that stops at
each review round for its supervisor's decision. zsh and `jq` are all they use, and none of them uses the network.

## Install

From this `copilot-cli` folder:

```sh
zsh install.sh            # copies into ~/.copilot/hooks, ~/.copilot/agents and ~/bin
zsh install.sh --check    # copies nothing; says which installed files differ from these
```

Then start the Copilot CLI again: it loads hooks and agents when it starts (`/env` lists them). VS Code's chat reads
`~/.copilot/hooks` too, so its sessions write status lines as well. Every path follows the CLI's own folder:
`$COPILOT_HOME` when it is set, else `~/.copilot` (the hook's command expands it the same way). The tools need zsh and
`jq` on `PATH`; the hook adds the usual system and Homebrew folders for a CLI that starts it with a short `PATH`.

## The status log

`agent-status.json` runs `agent-status.sh EVENT` on seven CLI hook events; each appends one line to
`~/.copilot/agent-status.log`:

```
14:06:26  build-api  STARTED  sessionStart
14:06:36  build-api  QUESTION  elicitation_dialog
```

| State | When |
|---|---|
| `RUNNING` | a prompt was submitted (also a queued one, and the turn a finished background shell starts) |
| `STARTED` | sessionStart, which the CLI sends with the session's first prompt |
| `QUESTION` | the agent asked a question in a dialog |
| `NEEDS-PERMISSION` | a tool, path or URL waits for approval |
| `IDLE` | the agent waits for input |
| `DONE` | the agent stopped (agentStop, or the agent_completed notification) |
| `CONTEXT-80` | the CLI is about to compact the conversation (it does so at about 80% of the context) |
| `ERROR`, `ENDED` | an error; the session ended |

- The name is the session's name (`/rename NAME`, or `copilot -n NAME`) in printable ASCII with spaces as underscores,
  at most 40 characters; without one, the first 8 characters of the session id. A subagent's run (a reviewer, say)
  logs under its own id. Give every session its own name before running several.
- A state repeated for the same session is written once. The detail is the event or notification type, never prompt,
  reply or tool text. The script takes about 0.1 s and always exits 0, so it never stops a session.
- Declining a permission ends the turn without agentStop, so the log keeps `NEEDS-PERMISSION` until the next prompt.
- `cplog` (or `cplog 30`) in a terminal split keeps the latest lines in sight.

## cpsig: a notification when a session wants attention

When the hook writes a new `DONE`, `QUESTION`, `NEEDS-PERMISSION` or `ERROR` line it also starts `~/bin/cpsig NAME
STATE` in the background (the session does not wait for it): a macOS notification titled `CPSIG` that reads, say,
`build-api DONE`. It stays in Notification Centre until closed, so it is seen even when the log is not watched.

- A state repeated for the same session is not written again, so it does not notify again either.
- `AGENT_STATUS_NOTIFY` in the CLI's environment names another program to start the same way (`NAME STATE` as its
  arguments), or turns notifications off when it is set but empty. Set it to `BIN/cpsig` when `install.sh` was given
  another folder.
- Without `osascript` (not macOS) `cpsig` does nothing; it always exits 0. The name and state go to AppleScript as
  arguments, never as script text.

## notify-done: a notification when a command has ended

`notify-done NAME COMMAND [ARG...]` runs the command, keeps its output and its exit code, and at the end adds a line to
the status log (`NAME  DONE  exit-0`, or `NAME  FAILED  exit-1`) and shows the same notification: for a test run or a
build in a terminal that is out of sight.

```sh
notify-done jest npx jest src/cart.test.ts
notify-done jest npx jest src/cart.test.ts > /tmp/j.txt 2>&1
```

Its last line is `notify-done NAME: EXIT n`. Ctrl+C ends the command and is reported as `FAILED` with exit code 130.
`AGENT_STATUS_NOTIFY` and `$COPILOT_HOME` hold here as for the hook.

## cpstatus and cpchat

- `cpstatus`: one line per session from the last 500 log lines, newest first: name, latest state, how long ago (the
  log keeps times only, so ages are for today).
- `cpchat [NAME|ID-PREFIX|.] [N] [-a] [-f]`: the last N (20) messages of a session's main conversation from
  `~/.copilot/session-state/<id>/events.jsonl`, in local time; a reply repeated back to back once. `-a` adds tool
  calls and prints a question (the `ask_user` tool) whole with its choices; `-f` prints long messages whole (else cut
  at 400 characters). Without a name, or with `.`, the newest session started in the current folder. The file is
  written as the session runs, so a reply is there within a second.

## The supervised-builder agent

`copilot --agent supervised-builder`, or `/agent supervised-builder` in a session. Its profile holds the run log and
status-file rules, questions logged as `Q` lines instead of built or asked in a dialog, and a review checkpoint: after
each review round it logs the verdict and one line per finding, fixes nothing, replies `REVIEW PASS` or
`WAITING REVIEW` and stops until it is told which findings to fix. The brief then needs only the task, its files, a
size budget and its checks. It sets no model, so the session keeps its own (a model in an agent's profile also resets
the reasoning effort to that model's default).

## Tests

`zsh test/copilot-cli.test.sh` runs every tool against sample payloads and session files in a temporary home folder.
