
// Test cases, appended after a script's JavaScript by test/run.sh, which renames
// the script's run() to main(). This run() is the one osascript calls. main() is
// only ever called through go(), with the pretend Application made by world(),
// so nothing here scripts an app.
var FAILS = [], PASSED = 0
function eq(name, got, want) {
  var g = JSON.stringify(got), w = JSON.stringify(want)
  if (g === w) PASSED++
  else FAILS.push('FAIL ' + name + ': got ' + g + ' want ' + w)
}
function has(f) { return typeof globalThis[f] == 'function' }
var EN = '\u2013', EM = '\u2014'
var NB = String.fromCharCode(0xa0), NNB = String.fromCharCode(0x202f), LRM = String.fromCharCode(0x200e), ZW = String.fromCharCode(0x200b)
function U(hex) { return '\\' + 'u' + hex }  // the six characters of an escape, as Browser Tabs prints them

// A pretend Application. apps: { '<app name>': { running, fail, se, windows: [{ name, urls, active }] } };
// an app that is not listed is not installed. se is what System Events reports for the app's
// windows: a list of titles, or an Error to throw. Everything the script does is added to log.
function world(apps, log) {
  function win(d, i) {
    var tabs = d.urls.map(function (u, t) { return 'tab' + (t + 1) })
    tabs.url = function () { return d.urls }
    var o = {
      tabs: tabs,
      activeTabIndex: function () { return d.active || 1 },
      currentTab: { index: function () { return d.active || 1 } }
    }
    return new Proxy(o, { set: function (x, k, v) { log.push('w' + (i + 1) + '.' + k + '=' + v); return true } })
  }
  function X(name) {
    if (name == 'System Events') {
      return { processes: new Proxy({}, { get: function (x, app) {
        return { windows: { name: function () {
          log.push('titles ' + app)
          var se = apps[app].se
          if (!se || se instanceof Error) throw se || new Error('no titles')
          return se
        } } }
      } }) }
    }
    var d = apps[name]
    if (!d) throw new Error('Application can\'t be found.')
    function check() { log.push('scan ' + name); if (d.fail) throw new Error('scan failed') }
    var windows = function () { check(); return d.windows.map(win) }
    windows.tabs = { url: function () { check(); return d.windows.map(function (x) { return x.urls }) } }
    Object.defineProperty(windows, 'name', { value: function () { return d.windows.map(function (x) { return x.name }) } })
    return {
      running: function () { return d.running !== false },
      windows: windows,
      activate: function () { log.push('activate ' + name) }
    }
  }
  X.currentApplication = function () { return { doShellScript: function (c) { log.push('sh ' + c) } } }
  return X
}
// Runs the script's own run() in a pretend world; returns its output and what it did (scans left out).
function go(args, apps) {
  var log = []
  var out = main(args, world(apps, log))
  return [out].concat(log.filter(function (l) { return !/^(scan|titles) /.test(l) }))
}

function run(argv) {
  var infoCache = argv[0], links = argv[1]

  // norm: lowercase scheme and host, drop default port, fragment, one trailing slash
  eq('norm case, port, slash, fragment', norm('HTTPS://Example.COM:443/Path/?Q=A#frag'), 'https://example.com/Path?Q=A')
  eq('norm http :80 and root slash', norm('http://Example.com:80/'), 'http://example.com')
  eq('norm keeps other ports', norm('https://example.com:8443/x/'), 'https://example.com:8443/x')
  eq('norm keeps :443 on http', norm('http://example.com:443/'), 'http://example.com:443')
  eq('norm root slash equal', norm('https://example.com'), norm('https://example.com/'))
  eq('norm query differs', norm('https://example.com/a?x=1') == norm('https://example.com/a?x=2'), false)
  eq('norm slash before query', norm('https://example.com/a/?x=1'), 'https://example.com/a?x=1')
  eq('norm query kept as is', norm('https://example.com/a?X=1/'), 'https://example.com/a?X=1/')
  eq('norm drops one slash only', norm('https://example.com/a//'), 'https://example.com/a/')
  eq('norm fragment only differs', norm('https://example.com/x#1'), norm('https://example.com/x#2'))
  eq('norm uppercase host and path', norm('HTTP://LOCALHOST:3000/App'), 'http://localhost:3000/App')
  eq('norm about:blank', norm('about:blank'), 'about:blank')
  eq('norm chrome page', norm('chrome://newtab/'), 'chrome://newtab')
  eq('norm empty', norm(''), '')

  // names: one row per profile of the info_cache that plutil extracts from test/local-state.json:
  // folder, name, gaia_name, gaia_given_name
  var N = names(infoCache)
  N.sort(function (a, b) { return a[0] < b[0] ? -1 : 1 })  // plutil does not keep JSON order
  eq('names', N.map(function (r) { return r.map(function (x) { return x || '' }) }), [
    ['Default', 'Personal', 'Sam Example', 'Sam'],
    ['Profile 1', 'Work', 'Sam Example', 'Sam'],
    ['Profile 2', 'Admin', '', ''],
    ['Profile 3', 'Test', 'Pat Tester', 'Pat'],
    ['Profile 5', 'Side Project', '', '']
  ])
  eq('names of nothing', names(''), [])
  eq('names without a name', names('{"Profile 4":{}}')[0].slice(0, 2), ['Profile 4', 'Profile 4'])
  // A real Chrome on 2026-11-21 (its names made up here): Local State, and the window titles Chrome and System Events gave.
  var LIVE = names(JSON.stringify({
    'Default': { name: 'Person 1', gaia_name: 'Robin Doe', gaia_given_name: 'Robin' },
    'Profile 1': { name: 'rdoe', gaia_name: 'Robin doe', gaia_given_name: 'Robin' },
    'Profile 2': { name: 'Kim', gaia_name: 'Kim Doe', gaia_given_name: 'Kim' },
    'Profile 3': { name: 'jo', gaia_name: 'jo', gaia_given_name: 'jo' },
    'Profile 5': { name: 'owl', gaia_name: '', gaia_given_name: '' },
    'Profile 8': { name: 'Your Chrome', gaia_name: '', gaia_given_name: '' },
    'Profile 9': { name: 'Person 2', gaia_name: '', gaia_given_name: '' }
  }))
  var LIVE_CHROME = ['about:blank', 'about:blank', 'about:blank', 'New tab']
  var LIVE_SE = [
    'about:blank - Google Chrome ' + EN + ' Your Chrome',
    'about:blank - Google Chrome ' + EN + ' Person 2',
    'about:blank - Google Chrome ' + EN + ' Your Chrome',
    'New tab - Google Chrome ' + EN + ' Robin',
    'Who\'s using Chrome?'
  ]
  var ONE = names('{"Default":{"name":"Person 1","gaia_name":"Sam Example","gaia_given_name":"Sam"}}')
  function f0(r) { return r ? r[0] : r }

  // folder: a profile by folder, name, gaia_name or gaia_given_name, any case; '' when two profiles fit
  eq('folder by name', f0(folder(N, 'work')), 'Profile 1')
  eq('folder by folder', f0(folder(N, 'PROFILE 2')), 'Profile 2')
  eq('folder name with space', f0(folder(N, 'side project')), 'Profile 5')
  eq('folder Default', f0(folder(N, 'default')), 'Default')
  eq('folder unknown', folder(N, 'nobody'), undefined)
  eq('folder by gaia_name', f0(folder(N, 'pat tester')), 'Profile 3')
  eq('folder by gaia_given_name', f0(folder(N, 'PAT')), 'Profile 3')
  eq('folder gaia_name of two profiles', folder(N, 'Sam Example'), '')
  eq('folder gaia_given_name of two profiles', folder(N, 'sam'), '')
  var CLASH = names('{"A":{"name":"Sam"},"B":{"name":"Work","gaia_name":"Sam","gaia_given_name":"Sam"}}')
  eq('folder name of one profile, gaia names of another: never picks one', folder(CLASH, 'sam'), '')
  eq('folder the other name of that pair', f0(folder(CLASH, 'WORK')), 'B')
  eq('folder same name twice', folder(names('{"A":{"name":"Work"},"B":{"name":"work"}}'), 'Work'), '')

  // prof: the profile of a System Events window title, "<page> - Google Chrome[ <dash> <profile>]"
  eq('prof en dash', f0(prof('Inbox - Google Chrome ' + EN + ' Work', N)), 'Profile 1')
  eq('prof em dash', f0(prof('Inbox - Google Chrome ' + EM + ' Work', N)), 'Profile 1')
  eq('prof hyphen', f0(prof('Inbox - Google Chrome - Work', N)), 'Profile 1')
  eq('prof lowercase title', f0(prof('Inbox - Google Chrome ' + EN + ' work', N)), 'Profile 1')
  eq('prof uppercase name in Local State', f0(prof('Inbox - Google Chrome ' + EN + ' Work', names('{"Default":{"name":"Me"},"Profile 9":{"name":"WORK"}}'))), 'Profile 9')
  eq('prof live titles', LIVE_SE.map(function (t) { return f0(prof(t, LIVE)) || '-' }), ['Profile 8', 'Profile 9', 'Profile 8', '-', '-'])
  eq('prof live: given name of two profiles stays unknown', prof('New tab - Google Chrome ' + EN + ' Robin', LIVE), '')
  eq('prof live: gaia_name of two profiles stays unknown', prof('New tab - Google Chrome ' + EN + ' Robin Doe', LIVE), '')
  eq('prof live: name, gaia_name and gaia_given_name alike', f0(prof('New tab - Google Chrome ' + EN + ' jo', LIVE)), 'Profile 3')
  eq('prof live: given name of one profile', f0(prof('New tab - Google Chrome ' + EN + ' Kim', LIVE)), 'Profile 2')
  eq('prof live: the profile picker', !!prof('Who\'s using Chrome?', LIVE), false)
  eq('prof name with space', f0(prof('Report - Google Chrome ' + EN + ' Side Project', N)), 'Profile 5')
  eq('prof gaia_name', f0(prof('Inbox - Google Chrome ' + EN + ' Pat Tester', N)), 'Profile 3')
  eq('prof gaia_given_name', f0(prof('Inbox - Google Chrome ' + EN + ' pat', N)), 'Profile 3')
  eq('prof gaia name of two profiles', !!prof('Inbox - Google Chrome ' + EN + ' Sam', N), false)
  eq('prof unknown name', !!prof('Inbox - Google Chrome ' + EN + ' Nobody', N), false)
  eq('prof private window', !!prof('Inbox - Google Chrome ' + EN + ' Work (Incognito)', N), false)
  eq('prof no suffix, several profiles', !!prof('Inbox - Google Chrome', N), false)
  eq('prof no suffix, one profile', f0(prof('Inbox - Google Chrome', ONE)), 'Default')
  eq('prof suffix, one profile', f0(prof('Inbox - Google Chrome ' + EN + ' Person 1', ONE)), 'Default')
  eq('prof other suffix, one profile', !!prof('Inbox - Google Chrome ' + EN + ' Guest', ONE), false)
  eq('prof no suffix, no Local State', !!prof('Inbox - Google Chrome', []), false)
  eq('prof page title only', !!prof('Jobs - Work', N), false)
  eq('prof page title naming a profile', !!prof('Jobs - Work - Google Chrome', N), false)
  eq('prof page title with dashes', f0(prof('A - Work ' + EN + ' Personal - Google Chrome ' + EN + ' Test', N)), 'Profile 3')
  eq('prof page title imitating a suffix', f0(prof('X - Google Chrome ' + EN + ' Work - Google Chrome ' + EN + ' Personal', N)), 'Default')
  eq('prof imitated suffix, one profile', f0(prof('X - Google Chrome ' + EN + ' Work - Google Chrome', ONE)), 'Default')
  eq('prof empty page title', f0(prof(' - Google Chrome ' + EN + ' Work', N)), 'Profile 1')
  eq('prof empty', !!prof('', N), false)
  eq('prof no title', !!prof(undefined, N), false)

  // pair: the System Events title of each Chrome window, '' unless it is certain
  var W = ' - Google Chrome ' + EN + ' Work', P = ' - Google Chrome ' + EN + ' Personal'
  eq('pair different titles', pair(['Inbox', 'News'], ['Inbox' + W, 'News' + P]), ['Inbox' + W, 'News' + P])
  eq('pair another order', pair(['Inbox', 'News'], ['News' + P, 'Inbox' + W]), ['Inbox' + W, 'News' + P])
  eq('pair same title, equal counts, one profile: paired', pair(['Doc', 'Doc', 'Inbox'], ['Doc' + W, 'Inbox' + P, 'Doc' + W]), ['Doc' + W, 'Doc' + W, 'Inbox' + P])
  eq('pair same title, equal counts, two profiles: unknown', pair(['Doc', 'Doc', 'Inbox'], ['Doc' + P, 'Inbox' + W, 'Doc' + W]), ['', '', 'Inbox' + W])
  eq('pair same title three times, one of another profile: unknown', pair(['Doc', 'Doc', 'Doc'], ['Doc' + W, 'Doc' + W, 'Doc' + P]), ['', '', ''])
  eq('pair same title, one with a profile and one without: unknown', pair(['Doc', 'Doc'], ['Doc' + W, 'Doc - Google Chrome']), ['', ''])
  eq('pair same title, no profile on either: paired', pair(['Doc', 'Doc'], ['Doc - Google Chrome', 'Doc - Google Chrome']), ['Doc - Google Chrome', 'Doc - Google Chrome'])
  eq('pair same title, the same profile written two ways: paired', pair(['Doc', 'Doc'], ['Doc - Google Chrome ' + EN + ' Work', 'Doc - Google Chrome ' + EM + ' WORK']).map(function (t) { return f0(prof(t, N)) }), ['Profile 1', 'Profile 1'])
  eq('pair same title, one title missing', pair(['Doc', 'Doc', 'Inbox'], ['Doc' + W, 'Inbox' + W]), ['', '', 'Inbox' + W])
  eq('pair same title, one title more', pair(['Doc', 'Inbox'], ['Doc' + W, 'Doc' + P, 'Inbox' + W]), ['', 'Inbox' + W])
  eq('pair empty Chrome name is never matched by its title', pair(['', '', 'Inbox'], ['Inbox' + W, W, W]), ['', '', 'Inbox' + W])
  eq('pair one window and one Chrome title left: paired', pair(['', 'Inbox'], ['Inbox' + W, W]), [W, 'Inbox' + W])
  eq('pair empty names on both sides', pair(['', ''], ['', '']), ['', ''])
  eq('pair missing Chrome name', pair([null, 'Inbox'], [null, 'Inbox' + W]), ['', 'Inbox' + W])
  eq('pair no titles', pair(['Inbox', 'Jobs - Work'], []), ['', ''])
  eq('pair title that starts another', pair(['Inbox', 'Inbox - Mail'], ['Inbox - Mail' + P, 'Inbox' + W]), ['Inbox' + W, 'Inbox - Mail' + P])
  eq('pair no suffix', pair(['Inbox'], ['Inbox - Google Chrome']), ['Inbox - Google Chrome'])
  eq('pair other window', pair(['Inbox'], ['Settings']), [''])
  eq('pair no windows', pair([], ['Inbox' + W]), [])
  eq('pair live: three same-title windows of two profiles are unknown, the picker left over', pair(LIVE_CHROME, LIVE_SE), ['', '', '', LIVE_SE[3]])
  eq('pair never guesses from the page title', pair(['Jobs - Work', 'News - Work'], ['Other' + P]).map(function (t) { return !!prof(t, N) }), [false, false])
  eq('pair one left on each side: the profile is the title\'s, not the page\'s', f0(prof(pair(['Jobs - Work'], ['Other' + P])[0], N)), 'Default')
  eq('pair one window left, two titles left', pair(['Jobs', 'Inbox'], ['Inbox' + W, 'Other' + P, 'More' + W]), ['', 'Inbox' + W])
  eq('pair two windows left, one title left', pair(['Jobs', 'News', 'Inbox'], ['Inbox' + W, 'Other' + P]), ['', '', 'Inbox' + W])
  eq('pair one window left, only another app\'s kind of title left', pair(['Jobs', 'Inbox'], ['Inbox' + W, 'Who\'s using Chrome?', 'Settings', '', null]), ['', 'Inbox' + W])

  // The same Chrome, second run (2026-11-21): the window showing the Python page was not paired.
  var IT = 'itertools ' + EM + ' Functions creating iterators for efficient looping ' + EM + ' Python 3.15.2 documentation'
  var MDN = 'Array.prototype.flatMap() - JavaScript | MDN'
  var RUN2 = [IT, MDN, 'about:blank', 'New tab']
  var RUN2_SE = [
    IT + ' - Google Chrome ' + EN + ' Your Chrome',
    MDN + ' - Google Chrome ' + EN + ' Person 2',
    'about:blank - Google Chrome ' + EN + ' Your Chrome',
    'New tab - Google Chrome ' + EN + ' Robin',
    'Who\'s using Chrome?'
  ]
  eq('pair run 2: same characters', pair(RUN2, RUN2_SE), RUN2_SE.slice(0, 4))
  // Two windows differ at once, so neither is the one-left case: these are paired by the normalising alone.
  var both = function (name) { return pair([name, MDN.replace(/ /g, NB), 'about:blank', 'New tab'], RUN2_SE) }
  eq('pair run 2: no-break spaces', both(IT.replace(/ /g, NB)), RUN2_SE.slice(0, 4))
  eq('pair run 2: narrow no-break spaces beside the dashes', both(IT.split(' ' + EM + ' ').join(NNB + EM + NNB)), RUN2_SE.slice(0, 4))
  eq('pair run 2: en dashes for em dashes', both(IT.split(EM).join(EN)), RUN2_SE.slice(0, 4))
  eq('pair run 2: hyphens for em dashes', both(IT.split(EM).join('-')), RUN2_SE.slice(0, 4))
  eq('pair run 2: horizontal bars and minus signs', both(IT.replace(EM, String.fromCharCode(0x2015)).replace(EM, String.fromCharCode(0x2212))), RUN2_SE.slice(0, 4))
  eq('pair run 2: doubled, leading and trailing spaces, a tab, a line break', both(' ' + IT.replace(' ' + EM + ' ', '  ' + EM + '\t').replace('for ', 'for\n') + ' '), RUN2_SE.slice(0, 4))
  eq('pair run 2: direction marks and zero-width characters', both(LRM + IT.replace('Functions', 'Func' + ZW + 'tions') + LRM), RUN2_SE.slice(0, 4))
  eq('pair run 2: capitals', both(IT.toUpperCase()), RUN2_SE.slice(0, 4))
  eq('pair run 2: the differences on the System Events side', pair(RUN2, [RUN2_SE[0].split(' ' + EM + ' ').join(NB + EN + NB), RUN2_SE[1].replace(/ /g, NNB)].concat(RUN2_SE.slice(2))).map(function (t) { return !!t }), [true, true, true, true])
  eq('pair run 2: another difference in one window: the one left, so paired', pair([IT.slice(0, 40)].concat(RUN2.slice(1)), RUN2_SE), RUN2_SE.slice(0, 4))
  eq('pair run 2: another difference in two windows: neither paired', pair([IT.slice(0, 40), MDN.slice(0, 20), 'about:blank', 'New tab'], RUN2_SE), ['', ''].concat(RUN2_SE.slice(2, 4)))
  eq('pair run 2: the profile picker is never the one left', pair([IT], ['Who\'s using Chrome?']), [''])

  // The same Chrome, third run: Chrome cuts the middle out of a long window name and puts an ellipsis there;
  // the System Events title is whole. (It was paired only as the one left.)
  var ELL = String.fromCharCode(0x2026)
  var IT_CUT = 'itertools ' + EM + ' Functions creating ' + ELL + ' ' + EM + ' Python 3.15.2 documentation'
  var FT = 'functools ' + EM + ' Higher-order functions and operations on callable objects ' + EM + ' Python 3.15.2 documentation'
  var FT_CUT = 'functools ' + EM + ' Higher-order functions ' + ELL + ' ' + EM + ' Python 3.15.2 documentation'
  var YC = ' - Google Chrome ' + EN + ' Your Chrome', P2 = ' - Google Chrome ' + EN + ' Person 2'
  eq('pair run 3: the exact pair', pair([IT_CUT], [RUN2_SE[0]]), [RUN2_SE[0]])
  eq('pair run 3: the four windows', pair([IT_CUT].concat(RUN2.slice(1)), RUN2_SE), RUN2_SE.slice(0, 4))
  eq('pair run 3: two cut names in two profiles at once', pair([IT_CUT, FT_CUT, 'about:blank'], [FT + P2, 'about:blank' + YC, IT + YC, 'Who\'s using Chrome?']), [IT + YC, FT + P2, 'about:blank' + YC])
  eq('prof run 3: two cut names in two profiles at once', pair([IT_CUT, FT_CUT], [FT + P2, IT + YC]).map(function (t) { return f0(prof(t, LIVE)) }), ['Profile 8', 'Profile 9'])
  eq('pair run 3: three dots for the ellipsis', pair([IT_CUT.replace(ELL, '...'), FT_CUT.replace(ELL, '...')], [FT + P2, IT + YC]), [IT + YC, FT + P2])
  eq('pair run 3: the same cut name twice, two titles of one profile: paired', pair([IT_CUT, IT_CUT, FT_CUT], [IT + YC, FT + P2, IT.replace('efficient', 'fast') + YC]), [IT + YC, IT.replace('efficient', 'fast') + YC, FT + P2])
  eq('pair run 3: the same cut name twice, two titles of two profiles: unknown', pair([IT_CUT, IT_CUT, FT_CUT], [IT + P2, FT + YC, IT.replace('efficient', 'fast') + YC]), ['', '', FT + YC])
  // Tab state that Chrome may add to the title System Events gives, before " - Google Chrome"
  eq('pair two windows with tab state in their titles', pair(['YouTube', 'Meet'], ['Meet - Camera recording' + P2, 'YouTube - Audio playing' + YC]), ['YouTube - Audio playing' + YC, 'Meet - Camera recording' + P2])
  eq('prof two windows with tab state in their titles', pair(['YouTube', 'Meet'], ['Meet - Camera recording' + P2, 'YouTube - Audio playing' + YC]).map(function (t) { return f0(prof(t, LIVE)) }), ['Profile 8', 'Profile 9'])
  eq('pair cut names with tab state', pair([IT_CUT, FT_CUT], [FT + ' - Audio playing' + P2, IT + ' - Network error' + YC]), [IT + ' - Network error' + YC, FT + ' - Audio playing' + P2])
  eq('pair tab state: a window whose own title is longer keeps its title', pair(['Song', 'Song - Live'], ['Song - Live' + YC, 'Song - Audio playing' + P2]), ['Song - Audio playing' + P2, 'Song - Live' + YC])
  eq('pair tab state: a title that two names fit goes to neither', pair(['Song', 'Song - Live', 'x'], ['Song - Live - Audio playing' + YC, 'x' + YC, 'y' + P2]), ['', '', 'x' + YC])
  eq('pair tab state: same name twice, two profiles: unknown', pair(['YouTube', 'YouTube', 'x'], ['YouTube - Audio playing' + YC, 'YouTube' + P2, 'x' + YC]), ['', '', 'x' + YC])
  eq('pair tab state needs the dash and spaces', pair(['You', 'Meet'], ['YouTube' + YC, 'Meetings' + P2]), ['', ''])
  eq('pair run 3: the same cut name twice, one title: neither', pair([IT_CUT, IT_CUT, FT_CUT], [IT + P2, FT + YC]), ['', '', FT + YC])
  eq('pair run 3: a cut name that fits two titles: not paired', pair([IT_CUT, FT_CUT], [IT + P2, IT.replace('efficient', 'fast') + YC, FT + YC]), ['', FT + YC])
  var ANY_CUT = 'i' + ELL + 'documentation'  // fits the first title, as IT_CUT does: neither may take it
  eq('pair run 3: a title that two cut names fit goes to neither', pair([IT_CUT, ANY_CUT, FT_CUT], [IT + P2, FT + YC, 'index of documentation' + YC]), ['', '', FT + YC])
  eq('pair run 3: the whole name is preferred to a cut one', pair(['a ' + ELL + ' z', 'a b z', 'q ' + ELL + ' r'], ['a b z' + P2, 'a c z' + YC, 'q x r' + YC]), ['a c z' + YC, 'a b z' + P2, 'q x r' + YC])
  eq('pair run 3: the start and the end must both fit', pair([IT_CUT, FT_CUT], ['x ' + IT + P2, IT + ' x' + P2, FT + YC]), ['', FT + YC])
  eq('pair run 3: a cut name is no pattern', pair(['C++ (what?) [x] ' + ELL + ' | end*', 'a.c ' + ELL + ' \\d$'], ['C++ (what?) [x] and more | end*' + YC, 'abc 1 2' + P2, 'a.c - \\d$' + P2, 'Cxx (what) [x] | end' + YC]), ['C++ (what?) [x] and more | end*' + YC, 'a.c - \\d$' + P2])
  // A page title with an ellipsis of its own
  var LOAD = 'Loading' + ELL + ' please wait', SOON = 'Coming soon...'
  eq('pair title with its own ellipsis', pair([LOAD, SOON, 'Loading'], ['Loading' + YC, SOON + P2, LOAD + YC]), [LOAD + YC, SOON + P2, 'Loading' + YC])
  eq('pair title with its own ellipsis beside one it could stand for', pair([LOAD, 'x'], ['Loading and loading, please wait' + P2, LOAD + YC, 'x' + YC]), [LOAD + YC, 'x' + YC])
  eq('pair title with its own ellipsis, three dots on one side', pair([LOAD, SOON], [SOON.replace('...', ELL) + P2, LOAD.replace(ELL, '...') + YC]), [LOAD.replace(ELL, '...') + YC, SOON.replace('...', ELL) + P2])
  eq('pair title with its own ellipsis, cut as well', pair(['Wait' + ELL + ' a very ' + ELL + ' the end', 'Wait' + ELL + ' b ' + ELL + ' end'], ['Wait' + ELL + ' b and more end' + P2, 'Wait' + ELL + ' a very long story, the end' + YC]), ['Wait' + ELL + ' a very long story, the end' + YC, 'Wait' + ELL + ' b and more end' + P2])
  eq('pair a name that is only an ellipsis, two titles', pair([ELL, 'x'], ['a' + YC, 'b' + P2, 'x' + YC]), ['', 'x' + YC])
  eq('prof run 2', pair(RUN2, RUN2_SE).map(function (t) { return f0(prof(t, LIVE)) || '-' }), ['Profile 8', 'Profile 9', 'Profile 8', '-'])
  eq('prof no-break spaces around the dash', f0(prof('Inbox - Google Chrome' + NB + EN + NNB + 'Your  Chrome', LIVE)), 'Profile 8')
  eq('prof direction marks around the name', f0(prof('Inbox - Google Chrome ' + EN + ' ' + LRM + 'Person 2' + LRM, LIVE)), 'Profile 9')
  eq('folder spaces and dashes in a name', f0(folder(names('{"A":{"name":"Side' + NB + EN + ' Project"},"B":{"name":"Other"}}'), 'side - project')), 'A')

  if (has('url')) {
    eq('url https', url('https://example.com/a?b=1#c'), 'https://example.com/a?b=1#c')
    eq('url http', url('http://x.example.org/z'), 'http://x.example.org/z')
    eq('url scheme in capitals', url('HTTPS://Example.com'), 'HTTPS://Example.com')
    eq('url http one-word host', url('http://intranet/wiki'), 'http://intranet/wiki')
    eq('url bare host', url('example.com'), 'https://example.com')
    eq('url bare host path query', url('Example.com/a?b=1#c'), 'https://Example.com/a?b=1#c')
    eq('url bare host port', url('example.com:8443/x'), 'https://example.com:8443/x')
    eq('url localhost port', url('localhost:3000'), 'http://localhost:3000')
    eq('url localhost port path', url('localhost:3000/x?y=1'), 'http://localhost:3000/x?y=1')
    eq('url localhost', url('localhost'), 'http://localhost')
    eq('url loopback port', url('127.0.0.1:8080'), 'http://127.0.0.1:8080')
    eq('url loopback port path', url('127.0.0.1:5173/app'), 'http://127.0.0.1:5173/app')
    eq('url address', url('10.0.0.1'), 'http://10.0.0.1')
    eq('url another address', url('10.15.7.1'), 'http://10.15.7.1')
    eq('url address port path', url('192.168.1.10:8443/x'), 'http://192.168.1.10:8443/x')
    eq('url five numbers', url('1.2.3.4.5'), '')
    eq('url numbers too long for an address', url('1234.1.1.1'), '')
    eq('url name under localhost', url('foo.localhost:3000'), 'http://foo.localhost:3000')
    eq('url names under localhost', url('a.b.localhost/x'), 'http://a.b.localhost/x')
    eq('url name under local', url('host.local:8080'), 'http://host.local:8080')
    eq('url name under local, path', url('printer.local/status'), 'http://printer.local/status')
    eq('url local alone', url('local'), '')
    eq('url word ending in localhost', url('mylocalhost'), '')
    eq('url host that only starts with local', url('host.localx.com'), 'https://host.localx.com')
    eq('url file names', ['notes.txt', 'README.md', 'package.json', 'app.js', 'main.ts', 'script.py', 'run.sh', 'error.log', 'data.csv', 'my.notes.TXT', 'a/b.txt', 'run.sh:1', 'notes.md/x'].map(url).join(''), '')
    eq('url file name with a scheme', url('https://example.md/x'), 'https://example.md/x')
    eq('url host with such a word inside', url('my.txt.example.com'), 'https://my.txt.example.com')
    eq('url host whose ending only starts like one', url('example.shop'), 'https://example.shop')
    eq('url host ending in letters and a digit', url('example.json5'), '')
    eq('url host ending in letters like one', ['example.mdx', 'example.logs', 'example.jsx', 'example.tsx', 'example.pyx'].map(url), ['https://example.mdx', 'https://example.logs', 'https://example.jsx', 'https://example.tsx', 'https://example.pyx'])
    eq('url scheme without a host', ['https:///', 'https://', 'http:///x', 'https://?q=1', 'https://#a', 'http:// x'].map(url).join(''), '')
    eq('url whole number', url('12345'), '')
    eq('url port alone', url('3000'), '')
    eq('url decimal', url('3.14'), '')
    eq('url longer decimal', url('10.25'), '')
    eq('url three numbers', url('1.2.3'), '')
    eq('url number and port', url('8080:80'), '')
    eq('url version number', url('v1.2'), '')
    eq('url version with digits', url('v1.25'), '')
    eq('url words', url('hello world'), '')
    eq('url one word', url('notes'), '')
    eq('url empty', url(''), '')
    eq('url mailto', url('mailto:a@example.com'), '')
    eq('url file', url('file:///etc/hosts'), '')
    eq('url javascript', url('javascript:alert(1)'), '')
    eq('url chrome page', url('chrome://settings'), '')
    eq('url ftp', url('ftp://example.com/x'), '')
    eq('url other scheme before a host', url('x-app://example.com'), '')
    eq('url https with a space', url('https://example.com/a b'), '')
    eq('url option-like word', url('-a Finder'), '')
  }

  if (has('target')) {
    eq('target link', target('gh', '', links), ['https://github.com', ''])
    eq('target link any case, arg profile', target('GH', 'work', links), ['https://github.com', 'work'])
    eq('target link profile', target('mail', '', links), ['https://mail.example.com/', 'Work'])
    eq('target arg profile wins', target('mail', 'Test', links), ['https://mail.example.com/', 'Test'])
    eq('target link bare host, folder profile', target('cal', '', links), ['https://calendar.example.com', 'Profile 2'])
    eq('target link profile with space', target('side', '', links), ['https://side.example.com', 'Side Project'])
    eq('target commented line ignored', target('old', '', links), 'ERR not a URL')
    eq('target commented name ignored', target('#off', '', links), 'ERR not a URL')
    eq('target comment after the URL', target('docs', '', links), ['https://docs.example.com/home', ''])
    eq('target comment after the profile, URL fragment kept', target('wiki', '', links), ['https://wiki.example.com/a#top', 'Work'])
    eq('target fragment is not a comment', target('frag', '', links), ['https://example.com/page#section', ''])
    eq('target comment right after a space', target('dev', '', links), ['http://localhost:3000/app', 'Test'])
    eq('target comment words are not names', target('the', '', links), 'ERR not a URL')
    eq('target link to another scheme', target('x', '', 'x file:///etc/hosts'), 'ERR not a URL')
    eq('target plain URL', target('example.org/x', '', links), ['https://example.org/x', ''])
    eq('target not a URL, not echoed', target('hello world', '', links), 'ERR not a URL')
    eq('target number, not echoed', target('4111111111111111', '', links), 'ERR not a URL')
    eq('target nothing', target('', '', links), 'ERR not a URL')
    eq('target no links file', target('gh', '', ''), 'ERR not a URL')
  }

  // Open URL's own run(), in pretend worlds. Its arguments: name or URL, profile, clipboard,
  // links.txt, lsappinfo's list, info_cache.
  if (has('target')) {
    var CHROME = 'ASN:0x0-0x1-"Raycast": ASN:0x0-0x2-"Google_Chrome": ASN:0x0-0x3-"Finder":'
    var FINDER = 'ASN:0x0-0x3-"Finder": ASN:0x0-0x2-"Google_Chrome":'
    var A = 'https://example.com/a'
    var args = function (a, p, clip, front) { return [a, p || '', clip || '', links, front || CHROME, infoCache] }
    var chrome = function (windows, se) { return { 'Google Chrome': { windows: windows, se: se } } }
    var two = [{ name: 'Inbox', urls: ['https://mail.example.com/', A + '/#x'] }, { name: 'Doc', urls: ['https://example.com/b', 'https://EXAMPLE.com:443/a'] }]

    eq('run reuses, un-minimizes, then raises',
      go(args(A), chrome(two, ['Inbox' + W, 'Doc' + P])),
      ['REUSED Chrome Work w1 t2 example.com/a', 'w1.activeTabIndex=2', 'w1.minimized=false', 'w1.index=1', 'activate Google Chrome'])
    eq('run reuses in the asked profile',
      go(args(A, 'personal'), chrome(two, ['Inbox' + W, 'Doc' + P])),
      ['REUSED Chrome Personal w2 t2 example.com/a', 'w2.activeTabIndex=2', 'w2.minimized=false', 'w2.index=1', 'activate Google Chrome'])
    eq('run asked profile by gaia name in the title',
      go(args(A, 'Test'), chrome(two, ['Inbox' + W, 'Doc - Google Chrome ' + EM + ' pat tester'])).slice(0, 2),
      ['REUSED Chrome Test w2 t2 example.com/a', 'w2.activeTabIndex=2'])
    eq('run open only in another profile: opens, sure',
      go(args(A, 'Test'), chrome(two, ['Inbox' + W, 'Doc' + P])),
      ['OPENED Chrome Test example.com/a', "sh open -na \"Google Chrome\" --args --profile-directory='Profile 3' 'https://example.com/a' >/dev/null 2>&1 &"])
    eq('run open in a window of no known profile: opens, unsure',
      go(args(A, 'Work'), chrome(two, ['Doc' + P])),
      ['OPENED? Chrome Work example.com/a', "sh open -na \"Google Chrome\" --args --profile-directory='Profile 1' 'https://example.com/a' >/dev/null 2>&1 &"])
    eq('run same-title windows, unequal counts: opens, unsure',
      go(args(A, 'Work'), chrome([{ name: 'Doc', urls: [A] }, { name: 'Doc', urls: ['https://example.com/b'] }], ['Doc' + W])),
      ['OPENED? Chrome Work example.com/a', "sh open -na \"Google Chrome\" --args --profile-directory='Profile 1' 'https://example.com/a' >/dev/null 2>&1 &"])
    eq('run same-title windows of one profile: reused',
      go(args(A, 'Work'), chrome([{ name: 'Doc', urls: ['https://example.com/b'] }, { name: 'Doc', urls: [A] }], ['Doc' + W, 'Doc' + W])).slice(0, 2),
      ['REUSED Chrome Work w2 t1 example.com/a', 'w2.activeTabIndex=1'])
    eq('run same-title windows of two profiles: opens, unsure',
      go(args(A, 'Work'), chrome([{ name: 'Doc', urls: [A] }, { name: 'Doc', urls: [A] }], ['Doc' + P, 'Doc' + W])),
      ['OPENED? Chrome Work example.com/a', "sh open -na \"Google Chrome\" --args --profile-directory='Profile 1' 'https://example.com/a' >/dev/null 2>&1 &"])
    eq('run window with tab state in its title',
      go(args(A, 'Work'), chrome([{ name: 'Doc', urls: [A] }, { name: 'Song', urls: [A] }], ['Doc - Audio playing' + P, 'Song - Audio playing' + W])).slice(0, 2),
      ['REUSED Chrome Work w2 t1 example.com/a', 'w2.activeTabIndex=1'])
    eq('run two windows without a name: opens, unsure',
      go(args(A, 'Work'), chrome([{ name: '', urls: [A] }, { name: '', urls: [] }], [W, W])).slice(0, 1),
      ['OPENED? Chrome Work example.com/a'])
    eq('run one window and one title left: paired',
      go(args(A, 'Work'), chrome([{ name: '', urls: [A] }], [W, 'Who\'s using Chrome?'])).slice(0, 1),
      ['REUSED Chrome Work w1 t1 example.com/a'])
    // Request 7 of the second run: open in Profile 8, w1 t3, behind the Python page. It was opened again.
    var run2 = function (name, p) {
      return go(['https://en.wikipedia.org/wiki/Version_control', p, '', '', CHROME, JSON.stringify(LIVE.reduce(function (o, r) { o[r[0]] = { name: r[1], gaia_name: r[2], gaia_given_name: r[3] }; return o }, {}))],
        chrome([{ name: name, urls: ['about:blank', 'https://example.com/b', 'https://en.wikipedia.org/wiki/Version_control', 'https://example.com/c', 'https://docs.python.org/3/library/itertools.html'], active: 5 },
          { name: MDN, urls: ['about:blank'] }, { name: 'about:blank', urls: ['about:blank'] }, { name: 'New tab', urls: ['chrome://newtab/'] }], RUN2_SE)).slice(0, 2)
    }
    eq('run 2: same characters', run2(IT, 'Profile 8'), ['REUSED Chrome Your Chrome w1 t3 en.wikipedia.org/wiki/Version_control', 'w1.activeTabIndex=3'])
    eq('run 2: no-break spaces in Chrome\'s name', run2(IT.replace(/ /g, NB), 'Profile 8'), ['REUSED Chrome Your Chrome w1 t3 en.wikipedia.org/wiki/Version_control', 'w1.activeTabIndex=3'])
    eq('run 2: another difference, the one window left', run2(IT.slice(0, 30), 'your chrome'), ['REUSED Chrome Your Chrome w1 t3 en.wikipedia.org/wiki/Version_control', 'w1.activeTabIndex=3'])
    eq('run 3: Chrome\'s cut name', run2(IT_CUT, 'Profile 8'), ['REUSED Chrome Your Chrome w1 t3 en.wikipedia.org/wiki/Version_control', 'w1.activeTabIndex=3'])
    var run3 = function (p) {
      return go(['https://en.wikipedia.org/wiki/Version_control', p, '', '', CHROME, JSON.stringify(LIVE.reduce(function (o, r) { o[r[0]] = { name: r[1], gaia_name: r[2], gaia_given_name: r[3] }; return o }, {}))],
        chrome([{ name: FT_CUT, urls: ['https://en.wikipedia.org/wiki/Version_control'] }, { name: IT_CUT, urls: ['about:blank', 'https://en.wikipedia.org/wiki/Version_control'] }], [IT + YC, FT + P2, 'Who\'s using Chrome?'])).slice(0, 2)
    }
    eq('run 3: two cut names in two profiles, asked for one', run3('Your Chrome'), ['REUSED Chrome Your Chrome w2 t2 en.wikipedia.org/wiki/Version_control', 'w2.activeTabIndex=2'])
    eq('run 3: two cut names in two profiles, asked for the other', run3('Profile 9'), ['REUSED Chrome Person 2 w1 t1 en.wikipedia.org/wiki/Version_control', 'w1.activeTabIndex=1'])
    eq('run 2: asked for the other profile: opened, sure', run2(IT.slice(0, 30), 'Person 2')[0], 'OPENED Chrome Person 2 en.wikipedia.org/wiki/Version_control')
    eq('run 2: the link whose toast was not seen', go(['bugs', '', '', 'bugs https://pypi.org/search/?q=requests&o=-created&c=Programming+Language+%3A%3A+Python Profile 8', CHROME, '{"Profile 8":{"name":"Your Chrome"},"Profile 9":{"name":"Person 2"}}'], chrome([{ name: 'about:blank', urls: ['about:blank'] }], ['about:blank - Google Chrome ' + EN + ' Your Chrome'])),
      ['OPENED Chrome Your Chrome pypi.org/search?q=requests&o=-created&c=Programming+Language',
        "sh open -na \"Google Chrome\" --args --profile-directory='Profile 8' 'https://pypi.org/search/?q=requests&o=-created&c=Programming+Language+%3A%3A+Python' >/dev/null 2>&1 &"])
    eq('run page title naming the profile is not trusted',
      go(args(A, 'Work'), chrome([{ name: 'Jobs - Work', urls: [A] }], [])).slice(0, 1),
      ['OPENED? Chrome Work example.com/a'])
    eq('run title with a gaia name of two profiles: opens, unsure',
      go(args('example.com/b', 'Work'), chrome(two, ['Inbox' + W, 'Doc - Google Chrome ' + EN + ' Sam'])).slice(0, 1),
      ['OPENED? Chrome Work example.com/b'])
    eq('run no titles, asked profile, open somewhere: opens, unsure, says why',
      go(args(A, 'Work'), chrome(two, new Error('not allowed'))),
      ['OPENED? Chrome Work example.com/a (no window titles)', "sh open -na \"Google Chrome\" --args --profile-directory='Profile 1' 'https://example.com/a' >/dev/null 2>&1 &"])
    eq('run no titles, asked profile, open nowhere: says so',
      go(args('https://example.com/zzz', 'Work'), chrome(two, new Error('not allowed'))).slice(0, 1),
      ['OPENED Chrome Work example.com/zzz (no window titles)'])
    eq('run no titles, no profile: reuses, says so',
      go(args(A), chrome(two, new Error('not allowed'))),
      ['REUSED Chrome - w1 t2 example.com/a (no window titles)', 'w1.activeTabIndex=2', 'w1.minimized=false', 'w1.index=1', 'activate Google Chrome'])
    eq('run one profile, titles without a suffix',
      go([A, 'person 1', '', '', CHROME, '{"Default":{"name":"Person 1"}}'], chrome(two, ['Inbox - Google Chrome', 'Doc - Google Chrome'])).slice(0, 1),
      ['REUSED Chrome Person 1 w1 t2 example.com/a'])
    eq('run asked profile looks at Chrome only',
      go(args(A, 'Work'), { 'Google Chrome': { windows: [], se: [] }, 'Brave Browser': { windows: [{ name: 'Doc', urls: [A] }] }, 'Safari': { windows: [{ name: 'Doc', urls: [A] }] } }),
      ['OPENED Chrome Work example.com/a', "sh open -na \"Google Chrome\" --args --profile-directory='Profile 1' 'https://example.com/a' >/dev/null 2>&1 &"])
    eq('run asked profile, Chrome not running',
      go(args(A, 'Profile 5'), { 'Google Chrome': { running: false, fail: true, windows: [] } }),
      ['OPENED Chrome Side Project example.com/a', "sh open -na \"Google Chrome\" --args --profile-directory='Profile 5' 'https://example.com/a' >/dev/null 2>&1 &"])
    var live = function (a, p) {
      return go([a, p, '', '', CHROME, JSON.stringify(LIVE.reduce(function (o, r) { o[r[0]] = { name: r[1], gaia_name: r[2], gaia_given_name: r[3] }; return o }, {}))],
        chrome([{ name: 'Doc', urls: [A] }, { name: 'Doc', urls: [A] }, { name: 'Doc', urls: ['https://example.com/b'] }, { name: 'New tab', urls: ['https://example.com/c'] }],
          ['Doc - Google Chrome ' + EN + ' Your Chrome', 'Doc - Google Chrome ' + EN + ' Person 2', 'Doc - Google Chrome ' + EN + ' Your Chrome', 'New tab - Google Chrome ' + EN + ' Robin', 'Who\'s using Chrome?']))
    }
    eq('run live: same-title windows of two profiles: unsure', live(A, 'person 2').slice(0, 1), ['OPENED? Chrome Person 2 example.com/a'])
    eq('run live: by folder, the same', live(A, 'Profile 8').slice(0, 1), ['OPENED? Chrome Your Chrome example.com/a'])
    eq('run live: open only in one of those windows: unsure', live('example.com/b', 'Person 2').slice(0, 1), ['OPENED? Chrome Person 2 example.com/b'])
    eq('run live: open in none of them: sure', live('example.com/zzz', 'Person 2').slice(0, 1), ['OPENED Chrome Person 2 example.com/zzz'])
    eq('run live: window titled Robin fits two profiles, so unsure', live('example.com/c', 'Person 1'),
      ['OPENED? Chrome Person 1 example.com/c', "sh open -na \"Google Chrome\" --args --profile-directory='Default' 'https://example.com/c' >/dev/null 2>&1 &"])
    eq('run live: asked for a name of two profiles', live(A, 'Robin'), ['ERR unknown profile: Robin'])
    eq('run live: no profile asked, unknown window reused', live('example.com/c', '').slice(0, 2), ['REUSED Chrome - w4 t1 example.com/c', 'w4.activeTabIndex=1'])
    eq('run unknown profile', go(args(A, 'Nobody'), chrome(two, [])), ['ERR unknown profile: Nobody'])
    eq('run profile name of two profiles', go(args(A, 'Sam'), chrome(two, [])), ['ERR unknown profile: Sam'])
    eq('run Safari: current tab, un-minimized',
      go(args(A, '', '', FINDER), { 'Safari': { windows: [{ name: 'Doc', urls: [null, A] }] } }),
      ['REUSED Safari - w1 t2 example.com/a', 'w1.currentTab=tab2', 'w1.miniaturized=false', 'w1.index=1', 'activate Safari'])
    eq('run frontmost browser first',
      go(args(A, '', '', 'ASN:0x0-0x1-"Raycast": ASN:0x0-0x2-"Brave_Browser":'), { 'Google Chrome': { windows: [{ name: 'Doc', urls: [A] }], se: ['Doc' + W] }, 'Brave Browser': { windows: [{ name: 'Doc', urls: [A] }] } }).slice(0, 2),
      ['REUSED Brave - w1 t1 example.com/a', 'w1.activeTabIndex=1'])
    eq('run frontmost app after Raycast, names with spaces',
      go(args(A, '', '', 'ASN:0x0-0x2-"Brave_Browser": ASN:0x0-0x1-"Raycast": ASN:0x0-0x3-"Google_Chrome":'), {}),
      ['OPENED Brave - example.com/a', "sh open -a \"Brave Browser\" 'https://example.com/a' >/dev/null 2>&1 &"])
    eq('run frontmost app is no browser: default browser, Chrome still scanned',
      go(args(A, '', '', FINDER), chrome(two, ['Inbox' + W, 'Doc' + P])).slice(0, 1), ['REUSED Chrome Work w1 t2 example.com/a'])
    eq('run no apps listed', go(args(A, '', '', ' '), {}), ['OPENED default - example.com/a', "sh open 'https://example.com/a' >/dev/null 2>&1 &"])
    eq('run line: URL without scheme, as compared, cut to 60',
      go(args('HTTPS://Example.com:443/' + 'p'.repeat(100) + '/#x', '', '', FINDER), {})[0], 'OPENED default - ' + ('example.com/' + 'p'.repeat(100)).slice(0, 60))
    eq('run nothing open: frontmost browser',
      go(args('example.org/x', '', '', 'ASN:0x0-0x2-"Brave_Browser":'), { 'Brave Browser': { windows: [] } }),
      ['OPENED Brave - example.org/x', "sh open -a \"Brave Browser\" 'https://example.org/x' >/dev/null 2>&1 &"])
    eq('run nothing open: default browser',
      go(args('', '', 'localhost:3000/it\'s', FINDER), {}),
      ['OPENED default - localhost:3000/it\'s', "sh open 'http://localhost:3000/it'\\''s' >/dev/null 2>&1 &"])
    eq('run browser that cannot be scanned: opens, unsure',
      go(args(A), { 'Google Chrome': { fail: true, windows: [] } }),
      ['OPENED? Chrome - example.com/a', "sh open -a \"Google Chrome\" 'https://example.com/a' >/dev/null 2>&1 &"])
    eq('run browser not running is left alone',
      go(args(A, '', '', FINDER), { 'Google Chrome': { running: false, fail: true, windows: [{ name: 'Doc', urls: [A] }] } }),
      ['OPENED default - example.com/a', "sh open 'https://example.com/a' >/dev/null 2>&1 &"])
    eq('run clipboard that is no URL: nothing opened, nothing echoed',
      go(args('', '', 'hunter2 4111111111111111'), chrome(two, [])), ['ERR not a URL'])
    eq('run clipboard with another scheme', go(args('', '', 'file:///etc/hosts'), chrome(two, [])), ['ERR not a URL'])
    eq('run clipboard with a file name', go(args('', '', 'notes.txt'), chrome(two, [])), ['ERR not a URL'])
    eq('run clipboard that was no text for osascript', go([null, null, null, links, CHROME, infoCache], chrome(two, [])), ['ERR not a URL'])
    eq('run clipboard line of 1,999 characters: opened',
      go(args('', '', 'https://example.com/' + 'a'.repeat(1979), FINDER), {})[1].length, "sh open '' >/dev/null 2>&1 &".length + 1999)
    eq('run clipboard line that fills the 2,000 the script reads: may be cut, so not opened',
      go(args('', '', 'https://example.com/' + 'a'.repeat(1980), FINDER), {}), ['ERR not a URL'])
    eq('run typed URL of 2,000 characters: opened',
      go(args('https://example.com/' + 'a'.repeat(1980), '', 'x'.repeat(2000), FINDER), {})[1].length, "sh open '' >/dev/null 2>&1 &".length + 2000)
    eq('run clipboard with a number', go(args('', '', '8080'), chrome(two, [])), ['ERR not a URL'])
    eq('run old check word is no longer special', go(args('?windows'), chrome(two, [])), ['ERR not a URL'])
  }

  if (has('report')) {
    var R1 = [
      { b: 'Chrome', p: 'Profile 1', w: 1, t: 1, a: true, u: 'https://Example.com/a/', s: 'A' + W },
      { b: 'Chrome', p: 'Profile 1', w: 1, t: 2, a: false, u: 'https://example.com/a#x', s: 'A' + W },
      { b: 'Chrome', p: 'Default', w: 2, t: 1, a: true, u: 'https://example.com/a', s: 'A' + P },
      { b: 'Chrome', p: undefined, w: 3, t: 1, a: true, u: 'chrome://newtab/', s: '' },
      { b: 'Chrome', p: undefined, w: 3, t: 2, a: false, u: 'https://example.com/a', s: '' },
      { b: 'Safari', p: 0, w: 1, t: 1, a: true, u: 'https://example.com:443/a', s: null },
      { b: 'Safari', p: 0, w: 1, t: 2, a: false, u: '', s: null },
      { b: 'Safari', p: 0, w: 1, t: 3, a: false, u: '', s: null },
      { b: 'Brave', p: 0, w: 1, t: 1, a: true, u: 'https://example.com/a?x=1', s: null },
      { b: 'Brave', p: 0, w: 1, t: 2, a: false, u: 'https://example.com/' + 'q'.repeat(100), s: null }
    ]
    eq('report: duplicates per profile, titles on first lines', report(R1, ['UNPAIRED Other' + W]).split('\n'), [
      'Chrome Profile 1 w1 t1* example.com/a | title: A' + W,
      'Chrome Profile 1 w1 t2 example.com/a',
      'Chrome Default w2 t1* example.com/a | title: A' + P,
      'Chrome - w3 t1* newtab | title: -',
      'Chrome - w3 t2 example.com/a',
      'Safari - w1 t1* example.com/a',
      'Safari - w1 t2 ',
      'Safari - w1 t3 ',
      'Brave - w1 t1* example.com/a?x=1',
      'Brave - w1 t2 ' + ('example.com/' + 'q'.repeat(100)).slice(0, 70),
      'DUP 2x Profile 1 https://example.com/a',
      'DUP 2x - https://example.com/a',
      'UNPAIRED Other' + W,
      'TABS 10 | WINDOWS 5 | DUPLICATES 2'
    ])
    eq('report same URL in two profiles is no duplicate', report([
      { b: 'Chrome', p: 'Profile 1', w: 1, t: 1, a: true, u: 'https://example.com/a', s: 'A' + W },
      { b: 'Chrome', p: 'Default', w: 2, t: 1, a: true, u: 'https://example.com/a', s: 'A' + P }
    ]).split('\n').slice(-1), ['TABS 2 | WINDOWS 2 | DUPLICATES 0'])
    eq('report empty', report([]), 'TABS 0 | WINDOWS 0 | DUPLICATES 0')

    // Browser Tabs' own run(), in pretend worlds. Its argument: info_cache.
    var cache = JSON.stringify(LIVE.reduce(function (o, r) { o[r[0]] = { name: r[1], gaia_name: r[2], gaia_given_name: r[3] }; return o }, {}))
    var T = function (s) { return ' - Google Chrome ' + EN + ' ' + s }
    var blank = function (active) { return { name: 'about:blank', urls: ['about:blank'], active: active } }
    eq('tabs live: a real Chrome: same-title windows of two profiles are unknown', go([cache], { 'Google Chrome': {
      windows: [blank(), blank(), blank(), { name: 'New tab', urls: ['chrome://newtab/'] }],
      se: LIVE_SE
    } })[0].split('\n'), [
      'Chrome - w1 t1* about:blank | title: -',
      'Chrome - w2 t1* about:blank | title: -',
      'Chrome - w3 t1* about:blank | title: -',
      'Chrome - w4 t1* newtab | title: New tab' + T('Robin'),
      'DUP 3x - about:blank',
      'UNPAIRED about:blank' + T('Your Chrome') + ' | "about:blank - Google Chrome ' + U('2013') + ' Your Chrome"',
      'UNPAIRED about:blank' + T('Person 2') + ' | "about:blank - Google Chrome ' + U('2013') + ' Person 2"',
      'UNPAIRED about:blank' + T('Your Chrome') + ' | "about:blank - Google Chrome ' + U('2013') + ' Your Chrome"',
      'UNPAIRED Who\'s using Chrome? | "Who\'s using Chrome?"',
      'NO TITLE w1 about:blank | "about:blank"',
      'NO TITLE w2 about:blank | "about:blank"',
      'NO TITLE w3 about:blank | "about:blank"',
      'TABS 4 | WINDOWS 4 | DUPLICATES 2'
    ])
    eq('tabs: same-title windows of one profile', go([cache], { 'Google Chrome': {
      windows: [blank(), blank(), { name: 'New tab', urls: ['chrome://newtab/'] }],
      se: ['about:blank' + T('Your Chrome'), 'New tab' + T('Person 2'), 'about:blank' + T('your chrome')]
    } })[0].split('\n'), [
      'Chrome Profile 8 w1 t1* about:blank | title: about:blank' + T('Your Chrome'),
      'Chrome Profile 8 w2 t1* about:blank | title: about:blank' + T('your chrome'),
      'Chrome Profile 9 w3 t1* newtab | title: New tab' + T('Person 2'),
      'DUP 2x Profile 8 about:blank',
      'TABS 3 | WINDOWS 3 | DUPLICATES 1'
    ])
    var w1 = function (name) { return { name: name, urls: ['about:blank', 'https://example.com/b', 'https://en.wikipedia.org/wiki/Version_control', 'https://example.com/c', 'https://docs.python.org/3/library/itertools.html'], active: 5 } }
    var rest = [{ name: MDN, urls: ['about:blank'] }, blank(), { name: 'New tab', urls: ['chrome://newtab/'] }]
    var head = function (first) {
      return [
        'Chrome ' + first, 'Chrome ' + first.slice(0, 9) + ' w1 t2 example.com/b', 'Chrome ' + first.slice(0, 9) + ' w1 t3 en.wikipedia.org/wiki/Version_control',
        'Chrome ' + first.slice(0, 9) + ' w1 t4 example.com/c', 'Chrome ' + first.slice(0, 9) + ' w1 t5* docs.python.org/3/library/itertools.html',
        'Chrome Profile 9 w2 t1* about:blank | title: ' + RUN2_SE[1],
        'Chrome Profile 8 w3 t1* about:blank | title: ' + RUN2_SE[2],
        'Chrome - w4 t1* newtab | title: ' + RUN2_SE[3]
      ]
    }
    var IT_ESC = 'itertools ' + U('2014') + ' Functions creating iterators for efficient looping ' + U('2014') + ' Python 3.15.2 documentation'
    eq('tabs run 2: same characters', go([cache], { 'Google Chrome': { windows: [w1(IT)].concat(rest), se: RUN2_SE } })[0].split('\n'),
      head('Profile 8 w1 t1 about:blank | title: ' + RUN2_SE[0]).concat([
        'DUP 2x Profile 8 about:blank',
        'UNPAIRED Who\'s using Chrome? | "Who\'s using Chrome?"',
        'TABS 8 | WINDOWS 4 | DUPLICATES 1'
      ]))
    eq('tabs run 2: no-break spaces: paired, and the characters shown', go([cache], { 'Google Chrome': { windows: [w1(IT.split(' ' + EM).join(NB + EM))].concat(rest), se: RUN2_SE } })[0].split('\n'),
      head('Profile 8 w1 t1 about:blank | title: ' + RUN2_SE[0]).concat([
        'DUP 2x Profile 8 about:blank',
        'UNPAIRED Who\'s using Chrome? | "Who\'s using Chrome?"',
        'INEXACT w1 "' + IT_ESC.split(' ' + U('2014')).join(U('00a0') + U('2014')) + '" | "' + IT_ESC + ' - Google Chrome ' + U('2013') + ' Your Chrome"',
        'TABS 8 | WINDOWS 4 | DUPLICATES 1'
      ]))
    eq('tabs run 3: Chrome\'s cut names: paired, and the characters shown', go([cache], { 'Google Chrome': { windows: [w1(IT_CUT), { name: FT_CUT, urls: ['about:blank'] }], se: [FT + P2, IT + YC] } })[0].split('\n'),
      head('Profile 8 w1 t1 about:blank | title: ' + IT + YC).slice(0, 5).concat([
        'Chrome Profile 9 w2 t1* about:blank | title: ' + FT + P2,
        'INEXACT w1 "itertools ' + U('2014') + ' Functions creating ' + U('2026') + ' ' + U('2014') + ' Python 3.15.2 documentation" | "' + IT_ESC + ' - Google Chrome ' + U('2013') + ' Your Chrome"',
        'INEXACT w2 "functools ' + U('2014') + ' Higher-order functions ' + U('2026') + ' ' + U('2014') + ' Python 3.15.2 documentation" | "functools ' + U('2014') + ' Higher-order functions and operations on callable objects ' + U('2014') + ' Python 3.15.2 documentation - Google Chrome ' + U('2013') + ' Person 2"',
        'TABS 6 | WINDOWS 2 | DUPLICATES 0'
      ]))
    eq('tabs run 2: two windows that differ otherwise: not paired, and the characters shown', go([cache], { 'Google Chrome': { windows: [w1(IT.slice(0, 11) + '"'), { name: 'MDN' + String.fromCharCode(0x2026), urls: ['about:blank'] }].concat(rest.slice(1)), se: RUN2_SE } })[0].split('\n'), [
      'Chrome - w1 t1 about:blank | title: -', 'Chrome - w1 t2 example.com/b', 'Chrome - w1 t3 en.wikipedia.org/wiki/Version_control', 'Chrome - w1 t4 example.com/c', 'Chrome - w1 t5* docs.python.org/3/library/itertools.html',
      'Chrome - w2 t1* about:blank | title: -',
      'Chrome Profile 8 w3 t1* about:blank | title: ' + RUN2_SE[2],
      'Chrome - w4 t1* newtab | title: ' + RUN2_SE[3],
      'DUP 2x - about:blank',
      'UNPAIRED ' + RUN2_SE[0] + ' | "' + IT_ESC + ' - Google Chrome ' + U('2013') + ' Your Chrome"',
      'UNPAIRED ' + RUN2_SE[1] + ' | "' + MDN + ' - Google Chrome ' + U('2013') + ' Person 2"',
      'UNPAIRED Who\'s using Chrome? | "Who\'s using Chrome?"',
      'NO TITLE w1 itertools ' + EM + '" | "itertools ' + U('2014') + '\\""',
      'NO TITLE w2 MDN' + String.fromCharCode(0x2026) + ' | "MDN' + U('2026') + '"',
      'TABS 8 | WINDOWS 4 | DUPLICATES 1'
    ])
    eq('tabs: a title missing, a title left over, other browsers', go([cache], {
      'Google Chrome': {
        windows: [blank(), blank(), { name: 'Doc', urls: ['https://example.com/a', 'https://example.com/b'], active: 2 }],
        se: ['about:blank' + T('Person 2'), 'Doc' + T('kim doe'), 'Settings', '']
      },
      'Brave Browser': { running: false, fail: true, windows: [] },
      'Safari': { windows: [{ name: 'Doc', urls: ['https://example.com/a', null], active: 2 }] }
    })[0].split('\n'), [
      'Chrome - w1 t1* about:blank | title: -',
      'Chrome - w2 t1* about:blank | title: -',
      'Chrome Profile 2 w3 t1 example.com/a | title: Doc' + T('kim doe'),
      'Chrome Profile 2 w3 t2* example.com/b',
      'Safari - w1 t1 example.com/a',
      'Safari - w1 t2* ',
      'DUP 2x - about:blank',
      'UNPAIRED about:blank' + T('Person 2') + ' | "about:blank - Google Chrome ' + U('2013') + ' Person 2"',
      'UNPAIRED Settings | "Settings"',
      'NO TITLE w1 about:blank | "about:blank"',
      'NO TITLE w2 about:blank | "about:blank"',
      'TABS 6 | WINDOWS 4 | DUPLICATES 1'
    ])
    eq('tabs: no titles', go([cache], { 'Google Chrome': { windows: [blank(), { name: 'Doc', urls: ['https://example.com/a'] }], se: new Error('Not allowed assistive access.') } })[0].split('\n'), [
      'Chrome - w1 t1* about:blank | title: -',
      'Chrome - w2 t1* example.com/a | title: -',
      'NO WINDOW TITLES: Not allowed assistive access.',
      'TABS 2 | WINDOWS 2 | DUPLICATES 0'
    ])
    eq('tabs: one profile, titles without a suffix', go(['{"Default":{"name":"Person 1"}}'], { 'Google Chrome': { windows: [blank()], se: ['about:blank - Google Chrome'] } })[0].split('\n'), [
      'Chrome Default w1 t1* about:blank | title: about:blank - Google Chrome',
      'TABS 1 | WINDOWS 1 | DUPLICATES 0'
    ])
    eq('tabs: nothing running', go([''], {}), ['TABS 0 | WINDOWS 0 | DUPLICATES 0'])
  }

  return FAILS.concat('PASS ' + PASSED + ' FAIL ' + FAILS.length).join('\n')
}
