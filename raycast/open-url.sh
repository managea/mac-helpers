#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title Open URL
# @raycast.mode compact
# @raycast.packageName Browser
# @raycast.argument1 {"type":"text","placeholder":"name [values] or URL","optional":true}
# @raycast.argument2 {"type":"text","placeholder":"profile","optional":true}
osascript -l JavaScript - "$1" "$2" "$(pbpaste|head -c 2000|head -1)" "$(cat ~/.config/open-url/links.txt 2>/dev/null)" "$(lsappinfo visibleProcessList)" \
 "$(plutil -extract profile.info_cache json -o - ~/Library/Application\ Support/Google/Chrome/Local\ State 2>/dev/null)" <<'JS'
function norm(u){var m=/^([\w+.-]+:\/\/[^\/?#]*)?([^?#]*)([^#]*)(#.*)?/.exec(u),f=m[4]||''
return(m[1]||'').toLowerCase().replace(/^(http:.*):80$|^(https:.*):443$/,'$1$2')+m[2].replace(/\/$/,'')+m[3]+(/^#[\w.-]*$/.test(f)?'':f)}
function url(a){var m=/^((([\w-]+\.)*localhost|([\w-]+\.)+local|\d{1,3}(\.\d{1,3}){3})|([\w-]+\.)+(?!(txt|md|json|js|ts|py|sh|log|csv)\b)[a-z]{2,})(:\d+)?([\/?#]\S*)?$/i.exec(a)
return/^https?:\/\/[^\s\/?#]\S*$/i.test(a)?a:m?'http'+(m[2]?'':'s')+'://'+a:''}
function target(a,p,t){var L=Object.create(null),w=a.split(/\s+/),v=w.slice(1),n=0,q=0,b='',r=''
for(var l of t.split('\n')){var f=l.replace(/(^|\s)#.*/,'').trim().split(/\s+/),k=f[0].toLowerCase()
if(f[1]&&!(k in L))L[k]=[f[1],f.slice(2).join(' ')]}
var e=L[w[0].toLowerCase()]
if(!e)return v[0]?'ERR not a URL':(a=url(a))?[a,p]:'ERR not a URL'
var x=(s,d)=>s.replace(/\{([\w.-]*)\}/g,(m,k)=>{if(!k)k=String(++q)
if(/^\d+$/.test(k))return n=Math.max(n,+k),v[k-1]||m
var c=L[k.toLowerCase()];if(!c||d>4)return b=b||'ERR '+(c?'links nested too deep at {'+k+'}':'no link {'+k+'}'),m
r=r||c[1];return x(c[0],d+1)})
a=x(e[0],0);if(b)return b
if(n!=v.length)return'ERR '+w[0]+(n?' needs '+n+' value'+(n>1?'s':''):' takes no values')
return(a=url(a))?[a,p||e[1]||r]:'ERR not a URL'}
var names=t=>Object.entries(JSON.parse(t||'{}')).map(([f,c])=>[f,c.name||f,c.gaia_name,c.gaia_given_name])
var nz=s=>(s||'').normalize('NFKC').replace(/[\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]/g,'').replace(/[\u2010-\u2015\u2212]/g,'-').replace(/\s+/g,' ').trim().toLowerCase(),folder=(N,p,k=N.filter(r=>r.some(x=>x&&nz(x)==nz(p))))=>k[1]?'':k[0]
var R=/^(?:(.*) )?- google chrome(?: - (.+))?$/
var prof=(t,N,m=R.exec(nz(t)))=>m?m[2]?folder(N,m[2]):N[1]?'':N[0]:''
function pair(C,A){var c=C.map(nz),m=A.map(y=>R.exec(nz(y))),P=c.map(x=>-1),f,g
for(var e of[0,1]){var M=c.map((x,i)=>m.flatMap((y,k)=>P[i]<0&&y&&y[1]&&!P.includes(k)&&(e?RegExp('^'+x.split('...').map(s=>s.replace(/[^\w ]/g,'\\$&')).join('.*')+'( - .*)?$').test(y[1]):x==y[1])?k:[]))
P=P.map((p,i)=>{var s=c.flatMap((y,j)=>y==c[i]?j:[])
return p<0&&M[i].length==s.length&&M[i].every(k=>m[k][2]==m[M[i][0]][2]&&M.every((J,j)=>c[j]==c[i]||!J.includes(k)))?M[i][s.indexOf(i)]:p})}
f=P.flatMap((j,i)=>j<0?i:[]);g=m.flatMap((y,k)=>y&&!P.includes(k)?k:[])
if(f.length*g.length==1)P[f[0]]=g[0]
return P.map(j=>j<0?'':A[j])}
function run(v,X){X=typeof X=='function'?X:Application;try{v=v.map(x=>(x||'').trim());var T=target(v[0]||(v[2][1999]?'':v[2]),v[1],v[3]),N=names(v[5]),k='',z='',b=x=>x.replace(/Google | Browser/,'')
if(!T.map)return T
var u=T[0],p=T[1],f=p&&folder(N,p),m=norm(u),d=' '+m.replace(/^.*?\/\//,'').slice(0,60)
if(p&&!f)return'ERR unknown profile: '+p
var S=X.currentApplication(),L=['Google Chrome','Brave Browser','Safari'],fr=(v[4].replace('"Raycast"','').split('"')[1]||'').replace(/_/g,' '),B=L.includes(fr)
S.includeStandardAdditions=true
for(var n of L.sort((x,y)=>(y==fr)-(x==fr))){try{var A=X(n),s=n[0]=='S',c=n[0]=='G',G=[];if(f&&!c||!A.running())continue}catch(e){continue}
try{var U=A.windows.tabs.url()
if(c)try{G=pair(A.windows.name(),X('System Events').processes[n].windows.name()).map(x=>prof(x,N))}catch(e){z=' (no window titles)'}
for(var i in U)for(var t in U[i])if(norm(U[i][t]||'')==m){if(f&&G[i]!=f){G[i]||(k='?');continue}
var w=A.windows()[i];s?w.currentTab=w.tabs[+t]:w.activeTabIndex=-~t
try{w[s?'miniaturized':'minimized']=false}catch(e){}
w.index=1;A.activate();return'REUSED '+b(n)+' '+(G[i]?G[i][1]:'-')+' w'+-~i+' t'+-~t+d+z}}catch(e){k='?'}}
var q=s=>"'"+s.replace(/'/g,"'\\''")+"'"
S.doShellScript((f?'open -na "Google Chrome" --args --profile-directory='+q(f[0])+' '+q(u):'open '+(B?'-a "'+fr+'" ':'')+q(u))+' >/dev/null 2>&1 &')
return'OPENED'+k+' '+(f?'Chrome '+f[1]:B?b(fr)+' -':'default -')+d+z}catch(e){return'ERR '+e.message}}
JS
