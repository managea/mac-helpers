#!/bin/zsh
# Offline tests. They run the scripts' JavaScript in osascript's JavaScript
# engine with a pretend Application (test/cases.js), so they never run a script
# and never script any app.
# Also checks the house rules: size, plain ASCII, zsh syntax, Raycast metadata, no credential words, a bounded clipboard.
cd "${0:A:h}/.." || exit 1
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
cache=$(plutil -extract profile.info_cache json -o - test/local-state.json) || { print "plutil failed"; exit 1 }
rc=0
for s in open-url.sh browser-tabs.sh; do
  # The JavaScript between <<'JS' and JS with its run() renamed main(), then the cases, whose run() is the one osascript calls.
  sed -n "/<<'JS'\$/,/^JS\$/p" $s | sed '1d;$d' | sed 's/^function run(/function main(/' > $tmp/$s.js
  # The cases hand main() a pretend Application. Run them only when the script can reach the real one
  # nowhere else: once, as the fallback when osascript passes a non-function second argument to run (X.currentApplication is the pretend one's).
  if [[ $(sed 's/X\.currentApplication//g' $tmp/$s.js | grep -o 'Application' | wc -l) -ne 1 ]] ||
     ! grep -q '^function main(v,X){X=typeof X==.function.?X:Application;' $tmp/$s.js; then
    print "$s: must name Application once, as the fallback for a non-function X in run(v,X); tests not run"; rc=1
  else
    cat test/cases.js >> $tmp/$s.js
    out=$(osascript -l JavaScript $tmp/$s.js "$cache" "$(<test/links.txt)" 2>&1)
    print -r -- "$s: $out"
    [[ $out == *'FAIL 0' ]] || rc=1
  fi
  zsh -n $s || { print "$s: zsh syntax error"; rc=1 }
  grep -q '^# @raycast.schemaVersion 1$' $s && grep -q '^# @raycast.packageName Browser$' $s ||
    { print "$s: Raycast metadata missing"; rc=1 }
  if grep -inE 'passw|secret|token|key|credential|auth' $s; then
    print "$s: a credential word (scripts hold no secrets)"; rc=1
  fi
  if grep -q pbpaste $s && ! grep -qF '"$(pbpaste|head -c 2000|head -1)"' $s; then
    print "$s: the clipboard must be read as pbpaste|head -c 2000|head -1 (a huge clipboard is an argument list too long)"; rc=1
  fi
  if LC_ALL=C grep -n '[^ -~]' $s; then
    print "$s: not plain ASCII"; rc=1
  fi
  print "$s: $(( $(wc -m < $s) )) characters"
done
(( rc )) && print FAILED || print OK
exit $rc
