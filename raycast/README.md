# Raycast scripts: Browser

Two Raycast script commands that open a URL with the fewest keystrokes and never load it twice.

| Script | Raycast title | Mode | What it does |
| --- | --- | --- | --- |
| `open-url.sh` | Open URL | compact | If the URL is already open in a tab of Chrome (any window, any profile), Brave or Safari, brings that tab to the front; otherwise opens it |
| `browser-tabs.sh` | Browser Tabs | fullOutput | Lists every tab, the URLs open more than once, and totals |

Each script stands alone (shared code is duplicated), stays short and is plain ASCII.

## Install

1. Make the scripts executable: `chmod +x raycast/*.sh` (from the repository's folder).
2. In Raycast: **Settings**, **Extensions**, **+**, **Add Script Directory**, and choose this `raycast` folder. Raycast lists only files with Raycast metadata, so the `test` folder and this README are not commands. Raycast can hold several script folders, so other scripts of your own can stay where they are.
3. Select **Open URL** in the Extensions list and **Record Hotkey** for it.
4. Optional: create `~/.config/open-url/links.txt` (below).

Raycast needs two permissions in **System Settings**, **Privacy & Security**:

- **Accessibility**: System Events reads Chrome's window titles through it, to tell the profiles apart.
- **Automation**, for each app the scripts control: Google Chrome, Brave Browser, Safari and System Events. macOS asks once for each on the first run that reaches it; allow them.

A browser that is not running is skipped without being launched.

## Open URL

Press the hotkey, then:

- **Enter** with both fields empty: opens the first line of the clipboard. Only the first 2,000 bytes of the clipboard are read; a first line that fills them may be cut, so it is `ERR not a URL` (type or link such a URL instead).
- A **name** from `links.txt` (with the words its places need, below), or a URL. Only `http://` and `https://` URLs are opened. After the scheme there must be a host (`https:///` is not a URL). A host without a scheme gets `https://` (`example.com/a`) when it ends in a dot and two or more letters that are not a common file ending (`txt`, `md`, `json`, `js`, `ts`, `py`, `sh`, `log`, `csv`: `notes.txt` is not a site; write `https://example.md` for one). `localhost`, names under `.localhost` and `.local`, and numeric addresses get `http://` (`localhost:3000`, `foo.localhost:3000`, `host.local:8080`, `127.0.0.1:8080`, `10.15.7.1`). A bare number, or dotted numbers that are not an address (`1.2.3`), are never a host. Anything else is `ERR not a URL`, without the text (it may be whatever was on the clipboard).
- Optionally a **profile** in the second field: a Chrome profile's folder (`Profile 1`) or name (`Work`, any case). It overrides the profile in `links.txt`.

What it does:

1. Compares URLs after normalizing them: lowercase scheme and host, no default port (`:80` for http, `:443` for https), no fragment that only names a place in the page (`#top`, `#section-2`; a fragment that is a route or a view, such as `#/functions/a`, `#!/a` or `#metricsV2:graph=...`, is kept: single-page apps tell their pages apart by it), one trailing slash of the path dropped; the query must match exactly.
2. Without a profile: scans Chrome, Brave and Safari, every window and tab, the frontmost browser first; any match counts. With a profile: scans Chrome only, and only a window known to belong to that profile counts.
3. A match: makes it the active tab, takes its window out of the Dock if it is minimized, raises it and brings the browser forward.
4. No match: with a profile, `open -na "Google Chrome" --args --profile-directory="<folder>" "<url>"`; without one, `open -a` the frontmost browser if it is Chrome, Brave or Safari (a new tab in its front window), else `open` in the default browser. `open` runs in the background, so the toast never waits for it (and an `open` that fails is not reported).

It prints one line, which Raycast shows as a toast:

```
REUSED <browser> <profile name or -> w<window> t<tab> <URL without scheme, cut to 60>
OPENED <browser or default> <profile name or -> <URL without scheme, cut to 60>
OPENED? ...
... (no window titles)
ERR <reason>
```

`OPENED?` means the URL was opened without knowing whether it was open already: with a profile, a Chrome window that shows the URL could not be matched to a profile; or a running browser could not be scanned. `(no window titles)` at the end of a line means System Events did not give Chrome's window titles (check the permissions above), so no window's profile is known.

Firefox has no tab scripting: it is opened (as the default browser) but never scanned.

### Which Chrome profile a window belongs to

Chrome's scripting lists the windows of all profiles but does not say which profile each belongs to. System Events reports a longer title for each window, `<page title> - Google Chrome – <profile>` when Chrome has several profiles (seen with an en dash; a hyphen or an em dash is accepted too) and `<page title> - Google Chrome` when it has one. The scripts read the profile from it:

Titles and names are compared after normalizing them: any case, every kind of dash as a hyphen, every kind of space (no-break spaces, tabs, line breaks) as one space, direction marks and zero-width characters dropped, compatibility forms folded (NFKC).

- `<profile>` is compared with each profile's folder, `name`, `gaia_name` and `gaia_given_name` in Chrome's `Local State` (Chrome shows `name` for a local profile and the given name for a signed-in one). If it fits two profiles (the same person signed in to both), the window's profile is unknown: one is never picked. The profile typed in **Open URL** is found the same way, so a name that fits two profiles is `ERR unknown profile`; use the folder.
- A title without a profile counts only when `Local State` has a single profile.
- A Chrome window is given the System Events title whose `<page title>` is its own title, and only when that is certain: windows with the same title are matched only when Chrome and System Events list the same number of them and those titles all name the same profile (so the order of the two lists does not matter); a window with an empty title is never matched this way.
- Chrome cuts the middle out of a long window title and puts an ellipsis there (`itertools — Functions creating … — Python 3.15.2 documentation`); the System Events title is whole. So a Chrome title with an ellipsis (or three dots) that fits no title as it is also fits a title that starts and ends as it does. Chrome may also add the tab's state to the title System Events gives (`YouTube - Audio playing - Google Chrome – Work`), so in this second step ` - <anything>` may follow the Chrome title. The same rule of certainty holds, and a System Events title that two different Chrome titles fit is given to neither.
- After that, when exactly one Chrome window and exactly one System Events title of that form are left, they are given to each other, whatever their page titles (a guard against differences not known yet). Other System Events windows (the profile picker) are ignored.
- The page title alone is never used. A window whose profile is unknown stays unknown: its line shows `-`, and a request for a profile never reuses its tabs.

System Events does not list windows on other Spaces or in full screen. Such a window has no title here, so its profile is unknown: a request for a profile, for a URL that is open in it, prints `OPENED?` and opens another tab. Without a profile it is reused as usual.

**Browser Tabs** prints each Chrome window's System Events title beside the profile found for it, to check this on a Mac.

## links.txt

`~/.config/open-url/links.txt`: one link per line, `name URL [profile]`. Names are matched in any case; `#` at the start of a line or after a space or tab starts a comment (a `#` inside a URL does not); the profile (name or folder, may contain spaces) is used unless the second field is filled.

```
# name  URL                                   profile
gh      https://github.com
mail    https://mail.example.com/             Work
cal     calendar.example.com                  Profile 2
docs    https://docs.example.com/home#team    Side Project   # a comment
```

**Shared parts and values.** A URL may hold `{name}`, the URL of another line (up to five deep), so a part that many links share is written once; a link without a profile of its own takes the profile of the first part it uses that has one. `{}` (in turn) or `{1}`, `{2}` ... stand for the words typed after the name in the first field, each word as typed, so one line serves every page that differs only by a name:

```
console  https://console.example.com              Work
fn       {console}/functions/home#/functions/{}
logs     {console}/logs/home#group/{1}/stream/{2}
```

`fn checkout` opens `https://console.example.com/functions/home#/functions/checkout` in Work; `logs api 2026-11-22` fills both. Places are numbered from `{1}`. A link given more or fewer words than it has places is `ERR needs 1 value`; words after a link without places are `ERR takes no values` (neither message repeats what was typed); `ERR no link {name}` names a part the file lacks. Values come only from the first field, never from the clipboard: with both fields empty the clipboard must be one URL or one name. A URL that holds a brace itself is written with `%7B` and `%7D`.

## Browser Tabs

```
<browser> <profile folder or -> w<window> t<tab>[*] <URL without scheme, cut to 70>[ | title: <System Events title or ->]
DUP <count>x <profile folder or -> <normalized URL>
UNPAIRED <System Events title> | "<the same, escaped>"
INEXACT w<window> "<Chrome's window title, escaped>" | "<System Events title, escaped>"
NO TITLE w<window> <Chrome's window title> | "<the same, escaped>"
NO WINDOW TITLES: <error>
TABS <n> | WINDOWS <n> | DUPLICATES <n>
```

`*` marks each window's active tab. The first line of each Chrome window ends with the System Events title matched to it, so the profile found can be checked against the title, for example `Chrome Profile 8 w2 t1* about:blank | title: about:blank - Google Chrome – Person 2`. `UNPAIRED` lists the System Events titles matched to no Chrome window, `NO TITLE` the Chrome windows given no title, and `INEXACT` the windows whose title was matched although its characters differ from Chrome's own (by the normalizing, for a title Chrome cut, or as the one left). Each shows the text as a JSON string with every character outside plain ASCII as `\uXXXX`, so the difference can be read. `NO WINDOW TITLES` is printed when System Events gave none.

A `DUP` line is printed for every normalized URL open more than once in the same profile: the same URL in two Chrome profiles is not a duplicate. Tabs without a known profile (`-`: Brave, Safari, and Chrome windows whose profile is unknown) are counted together. `DUPLICATES` counts the extra copies.

## Tests

`test/run.sh` runs offline on any Mac: it takes the JavaScript out of each script, renames its `run` to `main`, adds the cases in `test/cases.js` and runs them in `osascript -l JavaScript`. The cases test the pure functions (normalizing, URL rules, `links.txt` parsing, profile names from a sample Local State through `plutil`, the profile of a title, the pairing of windows, the report) and run each script's `main` in pretend worlds: `main` takes the `Application` function as its second argument, and the cases pass one that returns made-up browsers and System Events and records what the script does to them. The runner refuses to run a script that names `Application` anywhere else, so the tests never run a script and never script an app. It also checks each script's zsh syntax, Raycast metadata, banned words, plain ASCII, the bounded clipboard and size.

The cases include the window titles and Local State of the Mac the scripts were written for (2026-11-21).

How the real browsers and System Events answer is tested live only (un-minimizing and raising in each browser, the titles Chrome and System Events give).
