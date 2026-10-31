/* Tracks visible study time once across tabs; cumulative, user-scoped upserts. */
export function installRoutineTracker(client) {
 const key='tcego-routine-time-v1', leaseKey='tcego-routine-leader-v1', instance=crypto.randomUUID();
 const read=(k,d)=>{try{return JSON.parse(localStorage.getItem(k))||d}catch{return d}};
 let uid=null,eligible=false,paused=read('tcego-routine-paused',false),last=Date.now(),busy=false,current=null;
 const day=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Sao_Paulo'}).format(new Date());
 const panel=document.createElement('div');panel.id='routine-study-clock';panel.style.cssText='position:fixed;right:16px;bottom:90px;z-index:70;padding:10px 14px;border:1px solid var(--line,#bc9ddd);border-radius:16px;background:var(--card,#fff);color:var(--ink,#33233d);box-shadow:0 3px 18px #0002;font:13px sans-serif;max-width:290px';
 panel.innerHTML='<span id="routine-study-label"></span> <button id="routine-study-pause" type="button" style="padding:7px;border:0;border-radius:9px;cursor:pointer">Pausar</button><div id="routine-study-status" style="font-size:11px;margin-top:5px"></div>';
 document.body.append(panel);const label=panel.querySelector('#routine-study-label'),button=panel.querySelector('button'),status=panel.querySelector('#routine-study-status');
 const fmt=n=>`${Math.floor(n/3600)}h ${String(Math.floor(n/60)%60).padStart(2,'0')}min`;
 function save(rows){localStorage.setItem(key,JSON.stringify(rows))}
 function release(){const l=read(leaseKey,null);if(l?.id===instance)localStorage.removeItem(leaseKey)}
 function paint(){panel.hidden=!uid;button.textContent=paused?'Retomar':'Pausar';label.textContent=(paused?'Estudo pausado':eligible?'Tempo de estudo':'Contagem em espera')+' · '+fmt(read(key,[]).filter(r=>r.user_id===uid&&r.activity_date===day()).reduce((n,r)=>n+r.duration_seconds,0));}
 function tick(){const now=Date.now(),delta=Math.max(0,Math.min(5000,now-last));last=now;if(!uid||!eligible||paused||document.hidden){release();paint();return}
  const lease=read(leaseKey,null);if(lease&&lease.id!==instance&&now-lease.at<5000){paint();return}localStorage.setItem(leaseKey,JSON.stringify({id:instance,at:now}));
  const rows=read(key,[]);let row=rows.find(r=>r.session_id===current&&r.user_id===uid&&r.activity_date===day());
  if(!row){row={user_id:uid,session_id:crypto.randomUUID(),source:'tcego',category:'estudos',activity_date:day(),duration_seconds:0,completed_at:new Date().toISOString(),milliseconds:0};rows.push(row);current=row.session_id;}
  row.milliseconds=(row.milliseconds||row.duration_seconds*1000)+delta;row.duration_seconds=Math.min(86400,Math.floor(row.milliseconds/1000));row.completed_at=new Date().toISOString();save(rows);paint();
 }
 async function flush(){if(busy||!uid)return;busy=true;const owner=uid;try{const rows=read(key,[]).filter(r=>r.user_id===owner&&r.duration_seconds>0).map(({milliseconds,...r})=>r);for(let i=0;i<rows.length;i+=100){const {error}=await client.from('routine_time_sessions').upsert(rows.slice(i,i+100),{onConflict:'user_id,session_id'});if(error)throw error}status.textContent='Sincronizado com Minha Rotina';}catch{status.textContent='Salvo no aparelho · reenvio automático ao reconectar'}finally{busy=false}}
 button.onclick=()=>{tick();paused=!paused;localStorage.setItem('tcego-routine-paused',JSON.stringify(paused));paint();flush()};
 document.addEventListener('visibilitychange',()=>{last=Date.now();if(document.hidden){release();flush()}else{tick();flush()}});addEventListener('online',flush);addEventListener('pagehide',()=>{release();flush()});setInterval(tick,1000);setInterval(flush,15000);
 return {setContext(userId,active){if(uid!==userId){flush();release();current=null}uid=userId||null;eligible=!!active;last=Date.now();paint();flush()}};
}
