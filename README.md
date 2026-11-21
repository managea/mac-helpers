# Mac helpers

Small helpers for a Mac workstation, kept in one place. Each folder stands alone, has its own README and tests, and
installs on its own.

| Folder | What it is | Install | Tests |
| --- | --- | --- | --- |
| `copilot-cli/` | GitHub Copilot CLI status tools: a status log every session writes to (hooks), `cpstatus` (one line per session), `cpchat` (a session's conversation as text), and a supervised builder agent | `zsh copilot-cli/install.sh` (copies into `~/.copilot` and `~/bin`; `--check` copies nothing) | `zsh copilot-cli/test/copilot-cli.test.sh` |
| `raycast/` | Raycast script commands: **Open URL** (opens a link or reuses the tab that already shows it, in the right Chrome profile) and **Browser Tabs** (lists tabs and duplicates) | Add the `raycast` folder as a Raycast script directory; links in `~/.config/open-url/links.txt` | `zsh raycast/test/run.sh` |

Nothing here holds personal links, names or settings: those stay in your own files (`~/.config/open-url/links.txt`
and the like), outside the repository.
