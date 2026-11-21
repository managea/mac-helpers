#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title Browser Tabs
# @raycast.mode fullOutput
# @raycast.packageName Browser
osascript -l JavaScript - \
 "$(plutil -extract profile.info_cache json -o - ~/Library/Application\ Support/Google/Chrome/Local\ State 2>/dev/null)" <<'JS'
function norm(u){var m=/^([\w+.-]+:\/\/[^\/?#]*)?([^?#]*)([^#]*)/.exec(u)
return(m[1]||'').toLowerCase().replace(/^(http:.*):80$|^(https:.*):443$/,'$1$2')+m[2].replace(/\/$/,'')+m[3]}
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
function report(Q,x){var o=[],C={},d=0
for(var r of Q){var n=norm(r.u),p=r.p||'-',k=p+' '+n;if(n)C[k]=(C[k]||0)+1
o.push([r.b,p,'w'+r.w,'t'+r.t+(r.a?'*':''),n.replace(/^.*?\/\//,'').slice(0,70)].join(' ')+(r.t<2&&r.s!=null?' | title: '+(r.s||'-'):''))}
for(k in C)if(C[k]>1){o.push('DUP '+C[k]+'x '+k);d+=C[k]-1}
return o.concat(x||[],'TABS '+Q.length+' | WINDOWS '+new Set(Q.map(r=>r.b+r.w)).size+' | DUPLICATES '+d).join('\n')}
function run(v,X){X=typeof X=='function'?X:Application;try{var N=names(v[0]),Q=[],o=[]
for(var n of['Google Chrome','Brave Browser','Safari']){try{var A=X(n),b=n.replace(/Google | Browser/,''),P=0;if(!A.running())continue}catch(e){continue}
var W=A.windows()
if(b=='Chrome')try{var E=X('System Events').processes[n].windows.name(),C=A.windows.name(),J=x=>JSON.stringify(x).replace(/[^ -~]/g,c=>'\\u'+('000'+c.charCodeAt(0).toString(16)).slice(-4));P=pair(C,E)
o=E.filter(x=>x&&!P.includes(x)).map(x=>'UNPAIRED '+x+' | '+J(x)).concat(C.map((c,i)=>P[i]?P[i].indexOf(c+' - Google Chrome')?'INEXACT w'+(i+1)+' '+J(c)+' | '+J(P[i]):'':'NO TITLE w'+(i+1)+' '+c+' | '+J(c)).filter(x=>x))}catch(e){P=[];o=['NO WINDOW TITLES: '+e.message]}
for(var i=0;i<W.length;i++)try{var w=W[i],U=w.tabs.url(),a=b=='Safari'?w.currentTab.index():w.activeTabIndex()
U.forEach((u,t)=>Q.push({b:b,p:P&&(prof(P[i],N)||[])[0],w:i+1,t:t+1,a:t+1==a,u:u||'',s:P?P[i]||'':null}))}catch(e){}}
return report(Q,o)}catch(e){return'ERR '+e.message}}
JS
