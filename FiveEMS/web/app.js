const root = document.getElementById('root');
const frame = document.getElementById('deviceFrame');
const sidebar = document.getElementById('sidebar');
const content = document.getElementById('content');
const closeBtn = document.getElementById('closeBtn');
const contextBadge = document.getElementById('contextBadge');
const touchFinger = document.getElementById('touchFinger');
const toastHost = document.getElementById('toastHost');
const monitorOverlayEl = document.getElementById('monitorOverlay');

const state = {
  open:false,
  context:'os',
  extra:{},
  bootstrap:null,
  department:null,
  targetState:null,
  targetServerId:null,
  adminTab:'settings',
  creatorTab:'points',
  creatorStretcherVehicle:null,
  creatorView:'list',
  creatorCreating:false,
  creatorCareCreating:false,
  creatorGarageCreating:false,
  creatorGarageSelectedId:null,
  creatorGarageMode:'list',
  creatorSelectedId:null,
  patientTab:'xabcde',
  patientView:'scene',
  clinicalRegion:'chest',
  clinicalSceneActive:false,
  clinicalMarkerPositions:{},
  targetRef:null,
  medicalBag:{},
  clinicalCatalog:null,
  treatmentCatalog:null,
  defib:{rhythm:'--',shockable:false},
  csiEvidence:null,
  csiLabResult:null,
  settings:{},
  desktopApp:'settings',
  tabletApp:'home',
  desktopWindows:[],
  tabletWindows:[],
  osPrefs: loadPrefs(),
  audio:{playing:false,index:0,volume:0.7},
  settingsPane:'appearance',
  monitorUi:{frozen:false,muted:false,menu:false,nibpAt:0},
  monitorOverlay:loadMonitorOverlayPrefs(),
  monitorTargetState:null,
  monitorTargetRef:null,
  monitorPortableNetId:null,
  clinicalMarkerSmoothed:{},
  clinicalLabelSides:{},
  bedChart:null,
  bedChartTab:'summary',
};

const pointTypes = [
  ['duty','Bater ponto'],['supply','Medicamentos/equipamentos'],['director','Mesa da direcao'],
  ['computer','Computador'],['tablet','Tablet'],['monitor','Monitor multiparametrico'],['bed','Leito/cama'],['surgery','Mesa de cirurgia'],['iml','IML / mesa mortuaria'],['stretcher','Ponto de maca'],
  ['lab','Laboratorio CSI'],['evidence_locker','Armario de evidencias']
];
const permissionKeys = ['department.manage','staff.manage','ranks.manage','garage.use','garage.manage','supplies.use','supplies.manage','patient.assess','patient.treat','patient.advanced','reports.create','reports.view','stock.view','stock.manage','monitor.use','defib.use','csi.scene','csi.collect','csi.lab','admin.settings'];
const sceneRegionOrder = ['head','neck','left_arm','right_arm','chest','abdomen','pelvis','left_leg','right_leg','left_foot','right_foot'];

const garageTypes=[['car','Carros'],['motorcycle','Motos'],['aircraft','Aeronaves'],['boat','Barcos'],['truck','Caminhoes'],['bus','Onibus']];
const garageBlips=[
  [225,'Carro'],[226,'Moto'],[61,'Hospital'],[60,'Policia'],[67,'Caminhao/Entrega'],[410,'Marina/Barco'],[427,'Helicoptero'],[423,'Aviao'],[50,'Veiculo'],[1,'Padrao']
];
const garageColors=[[0,'Branco'],[1,'Vermelho'],[2,'Verde'],[3,'Azul'],[5,'Amarelo'],[15,'Ciano'],[17,'Laranja'],[26,'Azul eletrico'],[46,'Dourado'],[55,'Prata']];
const markerCatalog=[[0,'Cone invertido'],[1,'Cilindro'],[2,'Chevron'],[20,'Chevron simples'],[23,'Circulo horizontal'],[25,'Circulo fino'],[28,'Esfera'],[33,'Aviao'],[34,'Helicoptero'],[35,'Barco'],[36,'Carro'],[37,'Moto'],[39,'Caminhao']];
const pedCatalog=[['s_m_m_paramedic_01','Paramedico'],['s_m_y_fireman_01','Bombeiro'],['s_f_y_scrubs_01','Profissional hospitalar'],['s_m_m_security_01','Seguranca'],['s_m_m_highsec_01','Atendente masculino'],['s_f_y_cop_01','Atendente feminino']];
const garagePreviewModels={car:'ambulance',motorcycle:'policeb',aircraft:'frogger',boat:'dinghy',truck:'mule',bus:'bus'};

function esc(v=''){return String(v).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#039;','"':'&quot;'}[c]));}
function n(v,f=0){const x=Number(v);return Number.isFinite(x)?x:f;}
function orderedClinicalRegions(regions={}){const entries=Object.entries(regions||{}); return entries.sort((a,b)=>{const ai=sceneRegionOrder.indexOf(a[0]); const bi=sceneRegionOrder.indexOf(b[0]); return (ai<0?999:ai) - (bi<0?999:bi);});}
function loadPrefs(){try{return {...{language:'pt-BR',hour12:false,dateStyle:'short',wallpaper:'sand',tabletWallpaper:'midnight',accent:'#52a8ff',showWidgets:true,showDesktopIcons:true},...JSON.parse(localStorage.getItem('fiveems_os_prefs')||'{}')}}catch(e){return {language:'pt-BR',hour12:false,dateStyle:'short',wallpaper:'sand',tabletWallpaper:'midnight',accent:'#52a8ff',showWidgets:true,showDesktopIcons:true}}}
function savePrefs(){localStorage.setItem('fiveems_os_prefs', JSON.stringify(state.osPrefs||{}));}
function loadMonitorOverlayPrefs(){
  const defaults={enabled:false,compact:true,x:0.62,y:0.58,scale:0.62,locked:false};
  try{return {...defaults,...JSON.parse(localStorage.getItem('fiveems_monitor_overlay')||'{}'),enabled:false};}
  catch(e){return {...defaults};}
}
function saveMonitorOverlayPrefs(){
  const o=state.monitorOverlay||{};
  localStorage.setItem('fiveems_monitor_overlay',JSON.stringify({compact:!!o.compact,x:n(o.x,.62),y:n(o.y,.58),scale:n(o.scale,.62),locked:!!o.locked}));
}
function monitorOverlayActive(){return !!state.monitorOverlay?.enabled && !!state.monitorTargetState;}
function monitorAudioActive(){return state.context==='monitor' || monitorOverlayActive();}
function nui(event,data={}){return fetch(`https://${GetParentResourceName()}/${event}`,{method:'POST',headers:{'Content-Type':'application/json; charset=UTF-8'},body:JSON.stringify(data)}).then(r=>r.json()).catch(()=>({ok:false}));}
function toast(msg){const e=document.createElement('div');e.className='toast';e.textContent=msg;toastHost.appendChild(e);setTimeout(()=>e.remove(),3500);}
function setContext(ctx,extra={}){state.context=ctx;state.extra=extra||{};if(extra.targetServerId)state.targetServerId=Number(extra.targetServerId);if(ctx==='patient'){state.patientView='scene';state.clinicalRegion=null;state.clinicalSceneActive=false;}render();}
let closeInProgress=false;
function hardHideFiveEMS(){
  // clinical-scene-mode had a more specific `display:block!important` rule than
  // `.hidden`. Remove scene classes first, then apply the hard hidden state.
  root.classList.remove('clinical-scene-mode','os-transparent','monitor-live-mode');
  frame.classList.remove('scene-audit-shell','monitor-device-shell');
  root.classList.add('hidden');
  root.style.pointerEvents='none';
}
function close(forceFull=false){
  if(closeInProgress)return;
  closeInProgress=true;

  state.clinicalSceneActive=false;
  state.clinicalMarkerPositions={};
  state.clinicalMarkerSmoothed={};
  state.clinicalLabelSides={};
  clearInterval(waveTimer);
  clearInterval(sceneWaveTimer);

  const keepOverlay=!forceFull && monitorOverlayActive();
  if(keepOverlay){
    state.context='overlay';
    state.open=true;
    root.classList.remove('hidden');
    root.style.pointerEvents='none';
    frame.style.display='none';
    renderMonitorOverlay();
    nui('close',{keepMonitorOverlay:true}).finally(()=>{closeInProgress=false;});
    return;
  }

  state.open=false;
  state.monitorOverlay.enabled=false;
  state.monitorTargetState=null;
  state.monitorTargetRef=null;
  state.monitorPortableNetId=null;
  clearMonitorAudioTimers();
  clearInterval(monitorOverlayWaveTimer);monitorOverlayWaveTimer=null;
  hardHideFiveEMS();
  nui('close',{keepMonitorOverlay:false}).finally(()=>{closeInProgress=false;});
}

closeBtn.addEventListener('click',close);
document.addEventListener('keyup',e=>{if(e.key==='Escape'&&state.open)close();});
setInterval(()=>{document.getElementById('clock').textContent=new Date().toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'});},500);

document.addEventListener('mousemove',e=>{
  if(!frame.classList.contains('tablet')) return;
  const r=frame.getBoundingClientRect();
  touchFinger.style.left=`${e.clientX-r.left}px`;
  touchFinger.style.top=`${e.clientY-r.top}px`;
});
document.addEventListener('mousedown',()=>{ if(frame.classList.contains('tablet')) touchFinger.classList.add('active'); });
document.addEventListener('mouseup',()=>touchFinger.classList.remove('active'));


const playerTracks = [
  {title:'Helix 1', artist:'SoundHelix', url:'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'},
  {title:'Helix 2', artist:'SoundHelix', url:'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3'},
  {title:'Helix 3', artist:'SoundHelix', url:'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3'},
];
const musicAudio = new Audio();
musicAudio.preload = 'none';
musicAudio.volume = state.audio.volume;
musicAudio.addEventListener('ended', ()=>nextTrack());
function currentTrack(){ return playerTracks[state.audio.index] || playerTracks[0]; }
function applyTrack(){ const t=currentTrack(); musicAudio.src=t.url; musicAudio.volume=state.audio.volume; }
function playTrack(){ applyTrack(); musicAudio.play().catch(()=>{}); state.audio.playing=true; render(); }
function pauseTrack(){ musicAudio.pause(); state.audio.playing=false; render(); }
function nextTrack(){ state.audio.index=(state.audio.index+1)%playerTracks.length; if(state.audio.playing){ playTrack(); } else { applyTrack(); render(); } }
function prevTrack(){ state.audio.index=(state.audio.index-1+playerTracks.length)%playerTracks.length; if(state.audio.playing){ playTrack(); } else { applyTrack(); render(); } }
function osApps(mode='desktop'){
  const base = [
    {id:'finder', label:'Dashboard', icon:'⌂', color:'#74c2ff'},
    {id:'settings', label:'Ajustes', icon:'⚙', color:'#a285ff'},
    {id:'browser', label:'Navegador', icon:'🌐', color:'#66c1ff'},
    {id:'music', label:'Musica', icon:'♪', color:'#ff6b88'},
    {id:'patient', label:'Paciente', icon:'✚', color:'#2fd7ab'},
    {id:'calls', label:'Ocorrencias', icon:'☎', color:'#ffd166'},
    {id:'stock', label:'Estoque', icon:'💊', color:'#5aaeff'},
    {id:'chat', label:'Comunicacao', icon:'☁', color:'#ff9666'},
    {id:'csi', label:'CSI', icon:'⌕', color:'#b282ff'},
    {id:'reports', label:'Relatorios', icon:'▤', color:'#ff7598'},
    {id:'director', label:'Diretoria', icon:'♜', color:'#6ed18e'}
  ];
  return base;
}
function osWindowTitle(app){
  return ({finder:'Dashboard',settings:'Ajustes do Sistema',browser:'Navegador',music:'Musica',patient:'Prontuario / ePCR',calls:'Central de Ocorrencias',stock:'Estoque Clinico',chat:'Comunicacao Interna',csi:'Policia Cientifica / CSI',reports:'Relatorios',director:'Mesa do Diretor'})[app] || 'App';
}
function getWindows(mode){ return mode==='tablet' ? state.tabletWindows : state.desktopWindows; }
function setWindows(mode, list){ if(mode==='tablet') state.tabletWindows=list; else state.desktopWindows=list; }
function nextZ(mode){ const arr=getWindows(mode); return (arr.reduce((m,w)=>Math.max(m,w.z||1),1))+1; }
function defaultWindowGeometry(mode, app){
  const base = mode==='tablet' ? {x:60,y:80,w:760,h:500} : {x:120,y:90,w:880,h:560};
  const map={settings:{w:980,h:600},finder:{w:760,h:480},browser:{w:860,h:560},music:{w:500,h:420},patient:{w:900,h:600},calls:{w:760,h:500},stock:{w:760,h:480},chat:{w:680,h:440},csi:{w:820,h:520},reports:{w:760,h:480},director:{w:760,h:500}};
  return {...base,...(map[app]||{})};
}
function openOSApp(mode, app){
  let wins=getWindows(mode);
  const existing=wins.find(w=>w.app===app);
  if(existing){ existing.minimized=false; existing.z=nextZ(mode); render(); return; }
  const g=defaultWindowGeometry(mode,app);
  const newWin={id:Date.now()+Math.random(),app,title:osWindowTitle(app),x:g.x+Math.round(Math.random()*26),y:g.y+Math.round(Math.random()*20),w:g.w,h:g.h,z:nextZ(mode),minimized:false,maximized:false,data: app==='browser' ? {url:'https://example.org'} : {}};
  wins=[...wins,newWin]; setWindows(mode,wins); render();
}
function closeOSApp(mode,id){ setWindows(mode,getWindows(mode).filter(w=>w.id!==id)); render(); }
function focusOSApp(mode,id){ const wins=getWindows(mode); const win=wins.find(w=>w.id===id); if(!win) return; win.z=nextZ(mode); render(); }
function toggleMinimizeOSApp(mode,id){ const wins=getWindows(mode); const win=wins.find(w=>w.id===id); if(!win) return; win.minimized=!win.minimized; if(!win.minimized) win.z=nextZ(mode); render(); }
function toggleMaximizeOSApp(mode,id){ const wins=getWindows(mode); const win=wins.find(w=>w.id===id); if(!win) return; if(!win._restore){ win._restore={x:win.x,y:win.y,w:win.w,h:win.h}; } if(win.maximized && win._restore){ Object.assign(win, win._restore); win.maximized=false; } else { win.maximized=true; } win.z=nextZ(mode); render(); }
function updateWindowData(mode,id,patch){ const wins=getWindows(mode); const win=wins.find(w=>w.id===id); if(!win) return; win.data={...(win.data||{}),...(patch||{})}; render(); }
function formatClock(){ return new Date().toLocaleString(state.osPrefs.language||'pt-BR',{hour:'numeric',minute:'2-digit',hour12:!!state.osPrefs.hour12}); }
function formatDateLong(){ return new Date().toLocaleDateString(state.osPrefs.language||'pt-BR',{weekday:'short',month:'short',day:'numeric'}); }
function appMeta(id){ return osApps().find(a=>a.id===id) || {icon:'□',label:id,color:'#5aaeff'}; }
function osDashboardBody(mode){
  const apps=osApps(mode); const member=state.bootstrap?.member||{};
  return `<div class="wm-dashboard"><div class="wm-dashboard-hero"><div><div class="eyebrow">Workspace</div><h2>${mode==='tablet'?'Tablet Medical OS':'Computer Medical OS'}</h2><p>${esc(member.display_name||'Profissional')} · ${esc(member.department_name||'Sem departamento')}</p></div><div class="row"><span class="pill">Apps funcionais</span><span class="pill">Janelas arrastaveis</span></div></div><div class="wm-app-grid">${apps.filter(a=>a.id!=='finder').map(a=>`<button class="wm-app-card" data-open-app="${a.id}" style="--app-color:${a.color}"><span class="wm-app-icon">${a.icon}</span><strong>${esc(a.label)}</strong></button>`).join('')}</div></div>`;
}
function settingsWindowBody(mode){
  const p=state.osPrefs; const pane=state.settingsPane||'appearance';
  const paneBody = pane==='appearance' ? `
    <div class="grid two"><div class="card"><h3>Papel de parede do computador</h3>${selectField('Wallpaper','prefWallpaper',[['sand','Sand / macOS'],['midnight','Midnight'],['aurora','Aurora'],['hospital','Hospital Blue']],p.wallpaper)}<h3 style="margin-top:14px">Papel de parede do tablet</h3>${selectField('Wallpaper do tablet','prefTabletWallpaper',[['midnight','Midnight'],['sand','Sand'],['aurora','Aurora'],['hospital','Hospital Blue']],p.tabletWallpaper)}</div><div class="card"><h3>Personalizacao visual</h3>${field('Cor de destaque','prefAccent',p.accent,'color')}<label class="check"><input id="prefShowWidgets" type="checkbox" ${p.showWidgets?'checked':''}> Mostrar widgets de escritorio</label><label class="check"><input id="prefShowDesktopIcons" type="checkbox" ${p.showDesktopIcons?'checked':''}> Mostrar icones no escritorio/home</label></div></div>`
  : pane==='language' ? `
    <div class="grid two"><div class="card"><h3>Idioma</h3>${selectField('Idioma','prefLanguage',[['pt-BR','Portugues (Brasil)'],['en-US','English (US)'],['es-ES','Espanol']],p.language)}<p>O sistema operacional do FiveEMS usa este idioma para data, hora e interface basica.</p></div><div class="card"><h3>Regiao</h3><p>O formato de data e hora segue o locale selecionado.</p><p><b>Preview:</b> ${new Date().toLocaleString(p.language||'pt-BR')}</p></div></div>`
  : pane==='datetime' ? `
    <div class="grid two"><div class="card"><h3>Hora</h3>${selectField('Formato de hora','prefHour12',[[false,'24 horas'],[true,'12 horas']],String(p.hour12))}</div><div class="card"><h3>Data</h3>${selectField('Formato de data','prefDateStyle',[['short','Curta'],['medium','Media'],['long','Longa']],p.dateStyle)}<p><b>Preview:</b> ${new Date().toLocaleDateString(p.language||'pt-BR',{dateStyle:'full'})}</p></div></div>`
  : pane==='personalization' ? `
    <div class="grid two"><div class="card"><h3>Workspace</h3><p>Desktop e tablet compartilham o mesmo ecossistema de apps, com janelas arrastaveis, redimensionaveis e minimizaveis.</p><ul><li>Dock clicavel</li><li>Widgets opcionais</li><li>Atalhos no escritorio</li></ul></div><div class="card"><h3>Estado atual</h3><p><b>Wallpaper desktop:</b> ${esc(p.wallpaper)}</p><p><b>Wallpaper tablet:</b> ${esc(p.tabletWallpaper)}</p><p><b>Widgets:</b> ${p.showWidgets?'Ativos':'Ocultos'}</p><p><b>Icones:</b> ${p.showDesktopIcons?'Ativos':'Ocultos'}</p></div></div>`
  : `
    <div class="grid two"><div class="card"><h3>FiveEMS Medical OS</h3><p><b>Versao:</b> 0.1.6</p><p><b>Projeto:</b> Sasori's Development / FiveEMS</p><p><b>Contexto:</b> Computer OS, Tablet OS, monitor separado, hospital e CSI.</p></div><div class="card"><h3>Sobre</h3><p>Esta interface foi refinada para se aproximar de um sistema operacional com dock, janelas e ajustes de personalizacao.</p></div></div>`;
  return `<div class="wm-settings"><aside class="wm-settings-side">${[['appearance','Appearance'],['language','Language'],['datetime','Date & Time'],['personalization','Personalization'],['about','About']].map(([id,label])=>`<button class="wms-tab ${pane===id?'active':''}" data-settings-pane="${id}">${label}</button>`).join('')}</aside><section class="wm-settings-main"><div class="page-title"><div><h1>Ajustes do Sistema</h1><p>Personalize idioma, horario, data, papel de parede e comportamento visual do FiveEMS OS.</p></div><div class="row"><button class="btn primary" id="savePrefsBtn">Salvar preferencias</button></div></div>${paneBody}</section></div>`;
}
function browserWindowBody(win){ const url=win.data?.url || 'https://example.org'; return `<div class="browser-shell"><div class="browser-bar"><input id="browserUrl_${win.id}" value="${esc(url)}" placeholder="https://..." /><button class="btn small blue" data-browser-go="${win.id}">Ir</button><button class="btn small" data-browser-home="${win.id}">Home</button></div><div class="browser-quick row"><button class="btn small" data-browser-preset="${win.id}|https://example.org">Example</button><button class="btn small" data-browser-preset="${win.id}|https://www.wikipedia.org">Wikipedia</button><button class="btn small" data-browser-preset="${win.id}|https://www.openstreetmap.org">OpenStreetMap</button></div><div class="browser-frame"><iframe src="${esc(url)}" referrerpolicy="no-referrer"></iframe></div><p class="label" style="margin-top:8px">Alguns sites podem bloquear iframe dentro da NUI; nesse caso, teste outro endereco.</p></div>`; }
function musicWindowBody(){ const t=currentTrack(); return `<div class="music-shell"><div class="music-art">♪</div><div><div class="eyebrow">Now Playing</div><h2>${esc(t.title)}</h2><p>${esc(t.artist)}</p><div class="row"><button class="btn" id="prevTrackBtn">Anterior</button><button class="btn primary" id="playPauseTrackBtn">${state.audio.playing?'Pausar':'Tocar'}</button><button class="btn" id="nextTrackBtn">Proxima</button></div><div class="spacer"></div><label class="field"><label>Volume</label><input id="trackVolume" type="range" min="0" max="1" step="0.01" value="${n(state.audio.volume,0.7)}"></label><div class="table-wrap" style="margin-top:14px"><table><thead><tr><th>Faixa</th><th>Artista</th><th></th></tr></thead><tbody>${playerTracks.map((x,i)=>`<tr><td>${esc(x.title)}</td><td>${esc(x.artist)}</td><td><button class="btn small" data-play-track="${i}">Abrir</button></td></tr>`).join('')}</tbody></table></div></div></div>`; }
function genericAppBody(app){
  const d=state.department||{}; const member=state.bootstrap?.member||{}; const s=state.targetState?.state||state.targetState||null; const v=s?.vitals||{};
  if(app==='patient'){ return `<div class="os-app-pane"><div class="os-app-hero"><div><div class="eyebrow">Patient Workspace</div><h2>Prontuario / ePCR</h2><p>Atendimento, sinais, tratamentos, oxigenio e relatorio.</p></div><div class="row"><button class="btn primary" data-open-workspace="patient">Abrir workspace clinico</button></div></div>${s ? `${vitalsBlock(v)}<div class="spacer"></div><div class="grid two"><div class="card"><h3>Paciente carregado</h3><p>Server ID: ${esc(state.targetServerId||'---')}</p><p>Hemorragia: ${Math.round(n(s.totalBleeding||0)*10)/10}</p><p>Dor: ${Math.round(n(s.pain||0))}</p></div><div class="card"><h3>Acoes rapidas</h3><div class="row"><button class="btn blue" data-open-workspace="monitor">Abrir monitor</button><button class="btn" data-open-workspace="patient">Reabrir prontuario</button></div></div></div>` : `<div class="card"><h3>Nenhum paciente carregado</h3><p>Use <b>/fiveemsexam</b> ou <b>/fiveemspatient &lt;id&gt;</b> para carregar um paciente.</p></div>`}`; }
  if(app==='calls'){ return `<div class="os-app-pane"><div class="os-app-hero"><div><div class="eyebrow">Dispatch</div><h2>Central de Ocorrencias</h2><p>Use o comando de emergencia configurado pelo Admin para gerar um chamado.</p></div></div><div class="grid two"><div class="card"><h3>Despacho</h3><p>Modulo preparado para fila de chamadas, aceite e andamento.</p></div><div class="card"><h3>Atalhos</h3><p>Somente profissionais em servico devem receber o chamado.</p></div></div></div>`; }
  if(app==='stock'){ return `<div class="os-app-pane"><div class="page-title"><div><h1>Estoque Clinico</h1><p>Catalogo de medicamentos e equipamentos do departamento.</p></div></div><div class="table-wrap"><table><thead><tr><th>Item</th><th>Categoria</th><th>Qtd</th><th>Level</th></tr></thead><tbody>${(d.supplies||[]).map(s=>`<tr><td>${esc(s.label)}</td><td>${esc(s.category)}</td><td>${n(s.quantity)}</td><td>${n(s.min_level,1)}</td></tr>`).join('') || '<tr><td colspan="4">Nenhum item cadastrado.</td></tr>'}</tbody></table></div></div>`; }
  if(app==='chat'){ return `<div class="os-app-pane"><div class="page-title"><div><h1>Comunicacao Interna</h1><p>Mensageria entre medicos, enfermeiros, socorristas e setores.</p></div></div><div class="card"><h3>Status</h3><p>Nenhuma nova mensagem.</p><p>Planejado para integracao futura com canais internos.</p></div></div>`; }
  if(app==='csi'){ return `<div class="os-app-pane"><div class="os-app-hero"><div><div class="eyebrow">Forensics</div><h2>Policia Cientifica / CSI</h2><p>Vestigios, laboratorio e cadeia de custodia.</p></div><button class="btn primary" data-open-workspace="csi">Abrir modulo CSI</button></div><div class="grid three"><div class="card"><h3>Vestigios</h3><p>Coleta, foto e lacre.</p></div><div class="card"><h3>Laboratorio</h3><p>Analises de compatibilidade.</p></div><div class="card"><h3>Casos</h3><p>Laudos persistentes.</p></div></div></div>`; }
  if(app==='reports'){ return `<div class="os-app-pane"><div class="page-title"><div><h1>Relatorios</h1><p>ePCR, laudos e documentacao do FiveEMS.</p></div></div><div class="grid two"><div class="card"><h3>Clinico</h3><p>Baseado na ficha de trauma e no fluxo de atendimento.</p></div><div class="card"><h3>Producao</h3><p>XP por relatorios, transferencias e atendimentos concluidos.</p></div></div></div>`; }
  if(app==='director'){ return `<div class="os-app-pane"><div class="page-title"><div><h1>Mesa do Diretor</h1><p>Gestao de equipe, cargos e estrutura do departamento.</p></div><div class="row"><button class="btn primary" data-open-workspace="director">Abrir painel dedicado</button></div></div><div class="grid two"><div class="card"><h3>Departamento</h3><p>${esc(d.name||'---')}</p><p>${esc(d.type||'')}</p></div><div class="card"><h3>Profissional</h3><p>${esc(member.display_name||'---')}</p><p>${esc(member.rank_name||'Sem cargo')}</p></div></div></div>`; }
  return `<div class="card">Aplicativo em construcao.</div>`;
}
function osWindowBody(mode, win){
  if(win.app==='finder') return osDashboardBody(mode);
  if(win.app==='settings') return settingsWindowBody(mode);
  if(win.app==='browser') return browserWindowBody(win);
  if(win.app==='music') return musicWindowBody();
  return genericAppBody(win.app);
}
function renderOSWindow(mode, win){ const meta=appMeta(win.app); const classes=['os-win-instance',win.maximized?'maximized':'',win.minimized?'minimized':''].join(' '); const style=win.maximized ? `z-index:${win.z};` : `left:${win.x}px;top:${win.y}px;width:${win.w}px;height:${win.h}px;z-index:${win.z};`; return `<section class="${classes}" data-win-id="${win.id}" data-mode="${mode}" style="${style}"><header class="os-win-header" data-drag-handle="${win.id}"><div class="os-traffic"><button class="red" data-win-close="${win.id}"></button><button class="yellow" data-win-min="${win.id}"></button><button class="green" data-win-max="${win.id}"></button></div><div class="os-win-title"><span class="win-icon" style="--app-color:${meta.color}">${meta.icon}</span>${esc(win.title)}</div><div class="os-win-actions"><button class="ghostbtn" data-win-focus="${win.id}">▣</button></div></header><div class="os-win-content">${osWindowBody(mode,win)}</div><span class="os-win-resizer" data-resize-handle="${win.id}"></span></section>`; }
function wallpaperName(mode){ return mode==='tablet' ? (state.osPrefs.tabletWallpaper||'midnight') : (state.osPrefs.wallpaper||'sand'); }
function renderOSStage(mode){
  const member=state.bootstrap?.member||{}; const dept=state.department||{}; const wins=getWindows(mode).filter(w=>!w.minimized).sort((a,b)=>(a.z||1)-(b.z||1)); const apps=osApps(mode); const clock=formatClock(); const showWidgets=state.osPrefs.showWidgets!==false; const showIcons=state.osPrefs.showDesktopIcons!==false;
  const icons = apps.map(a=>`<button class="${mode==='tablet'?'ipad-dock-item':'os-dock-item'}" data-open-app="${a.id}" title="${esc(a.label)}" style="--app-color:${a.color}"><span class="${mode==='tablet'?'':'dock-ico'}">${a.icon}</span>${mode==='tablet'?'':`<span class="dock-tip">${esc(a.label)}</span>`}</button>`).join('');
  const minimized = getWindows(mode).filter(w=>w.minimized).map(w=>`<button class="mini-chip" data-restore-win="${w.id}">${esc(w.title)}</button>`).join('');
  const desktopShortcuts = showIcons ? `<div class="desktop-shortcuts">${apps.filter(a=>!['finder'].includes(a.id)).slice(0,7).map(a=>`<button class="desktop-shortcut" data-open-app="${a.id}" style="--app-color:${a.color}"><span class="desktop-shortcut-icon">${a.icon}</span><span>${esc(a.label)}</span></button>`).join('')}</div>` : '';
  const tabletIcons = showIcons ? `<div class="tablet-app-grid">${apps.filter(a=>!['finder'].includes(a.id)).map(a=>`<button class="tablet-home-app" data-open-app="${a.id}" style="--app-color:${a.color}"><span class="tablet-home-icon">${a.icon}</span><span>${esc(a.label)}</span></button>`).join('')}</div>` : '';
  if(mode==='tablet'){
    return `<div class="tablet-stage"><div class="tablet-shell" data-wallpaper="${wallpaperName(mode)}" style="--user-accent:${state.osPrefs.accent}"><div class="tablet-bg"></div><div class="tablet-topbar"><span>${formatDateLong()}</span><div class="tablet-topicons"><span>${esc(member.department_name||'FiveEMS')}</span><span>${clock}</span></div></div>${showWidgets?`<div class="tablet-widget-main"><div><div class="eyebrow">Touch workspace</div><h2>${esc(member.display_name||'Profissional')}</h2><p>${esc(dept.name||'Sem departamento')}</p></div><span class="pill">Monitor separado</span></div>`:''}${tabletIcons}<div class="tablet-workarea">${wins.map(w=>renderOSWindow(mode,w)).join('')}</div><div class="tablet-minibar">${minimized}</div><div class="tablet-dock">${icons}</div><div class="tablet-home-indicator"></div></div></div>`;
  }
  return `<div class="desktop-stage"><div class="desktop-shell" data-wallpaper="${wallpaperName(mode)}" style="--user-accent:${state.osPrefs.accent}"><div class="desktop-bg"></div><div class="os-menubar"><div class="os-menu-left"><span class="apple-mark">✦</span><span>Finder</span><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span><span>Help</span></div><div class="os-menu-right"><span>${esc(member.department_name||'FiveEMS')}</span><span>${clock}</span></div></div>${showIcons?desktopShortcuts:''}${showWidgets?`<div class="os-quick-widget left"><div class="widget-icon">✉</div><div><b>Mail</b><small>All caught up</small></div></div><div class="os-quick-widget right"><div class="widget-preview"><p>${esc(dept.name||'FiveEMS')}</p><small>${member.on_duty?'Em servico':'Fora de servico'}</small><small>${formatDateLong()}</small></div></div>`:''}<div class="desktop-workarea">${wins.map(w=>renderOSWindow(mode,w)).join('')}</div><div class="desktop-minibar">${minimized}</div><div class="os-dock">${icons}</div></div></div>`;
}
function attachOSInteractions(mode){
  const container=content;
  const stage=container.querySelector(mode==='tablet'?'.tablet-shell':'.desktop-shell');
  if(!stage) return;
  container.querySelectorAll('[data-open-app]').forEach(b=>b.onclick=()=>openOSApp(mode,b.dataset.openApp));
  container.querySelectorAll('[data-restore-win]').forEach(b=>b.onclick=()=>toggleMinimizeOSApp(mode, Number(b.dataset.restoreWin)));
  container.querySelectorAll('[data-win-close]').forEach(b=>b.onclick=(e)=>{e.stopPropagation(); closeOSApp(mode, Number(b.dataset.winClose));});
  container.querySelectorAll('[data-win-min]').forEach(b=>b.onclick=(e)=>{e.stopPropagation(); toggleMinimizeOSApp(mode, Number(b.dataset.winMin));});
  container.querySelectorAll('[data-win-max]').forEach(b=>b.onclick=(e)=>{e.stopPropagation(); toggleMaximizeOSApp(mode, Number(b.dataset.winMax));});
  container.querySelectorAll('[data-win-focus]').forEach(b=>b.onclick=(e)=>{e.stopPropagation(); focusOSApp(mode, Number(b.dataset.winFocus));});
  container.querySelectorAll('[data-open-workspace]').forEach(b=>b.onclick=()=>setContext(b.dataset.openWorkspace,{}));
  container.querySelectorAll('[data-settings-pane]').forEach(b=>b.onclick=()=>{ state.settingsPane=b.dataset.settingsPane; render(); });
  const settingsSave=container.querySelector('#savePrefsBtn');
  if(settingsSave){ settingsSave.onclick=()=>{ const get=(id)=>document.getElementById(id); if(get('prefLanguage')) state.osPrefs.language=get('prefLanguage').value; if(get('prefHour12')) state.osPrefs.hour12=get('prefHour12').value==='true'; if(get('prefDateStyle')) state.osPrefs.dateStyle=get('prefDateStyle').value; if(get('prefWallpaper')) state.osPrefs.wallpaper=get('prefWallpaper').value; if(get('prefTabletWallpaper')) state.osPrefs.tabletWallpaper=get('prefTabletWallpaper').value; if(get('prefAccent')) state.osPrefs.accent=get('prefAccent').value; if(get('prefShowWidgets')) state.osPrefs.showWidgets=get('prefShowWidgets').checked; if(get('prefShowDesktopIcons')) state.osPrefs.showDesktopIcons=get('prefShowDesktopIcons').checked; savePrefs(); render(); }; }
  container.querySelectorAll('[data-browser-go]').forEach(b=>b.onclick=()=>{const id=Number(b.dataset.browserGo); const input=document.getElementById(`browserUrl_${id}`); let url=(input?.value||'').trim(); if(url && !/^https?:\/\//i.test(url)) url='https://' + url; updateWindowData(mode,id,{url:url||'https://example.org'});});
  container.querySelectorAll('[data-browser-home]').forEach(b=>b.onclick=()=>updateWindowData(mode,Number(b.dataset.browserHome),{url:'https://example.org'}));
  container.querySelectorAll('[data-browser-preset]').forEach(b=>b.onclick=()=>{const [id,url]=b.dataset.browserPreset.split('|'); updateWindowData(mode,Number(id),{url});});
  const playPause=container.querySelector('#playPauseTrackBtn'); if(playPause) playPause.onclick=()=>{ state.audio.playing ? pauseTrack() : playTrack(); };
  const prev=container.querySelector('#prevTrackBtn'); if(prev) prev.onclick=prevTrack;
  const next=container.querySelector('#nextTrackBtn'); if(next) next.onclick=nextTrack;
  const vol=container.querySelector('#trackVolume'); if(vol) vol.oninput=()=>{ state.audio.volume=n(vol.value,0.7); musicAudio.volume=state.audio.volume; if(state.audio.playing) musicAudio.volume=state.audio.volume; };
  container.querySelectorAll('[data-play-track]').forEach(b=>b.onclick=()=>{ state.audio.index=n(b.dataset.playTrack); playTrack(); });
  const workArea=container.querySelector(mode==='tablet'?'.tablet-workarea':'.desktop-workarea');
  container.querySelectorAll('.os-win-instance').forEach(winEl=>{
    const id=Number(winEl.dataset.winId);
    winEl.addEventListener('mousedown',()=>{ const arr=getWindows(mode); const win=arr.find(w=>w.id===id); if(win){ win.z=nextZ(mode); winEl.style.zIndex=win.z; }});
    const header=winEl.querySelector('[data-drag-handle]');
    if(header){ header.ondblclick=(e)=>{ if(!e.target.closest('button')) toggleMaximizeOSApp(mode,id); }; header.onmousedown=(e)=>{ if(e.target.closest('button')) return; const arr=getWindows(mode); const win=arr.find(w=>w.id===id); if(!win || win.maximized) return; const rect=winEl.getBoundingClientRect(); const areaRect=workArea.getBoundingClientRect(); const startX=e.clientX, startY=e.clientY, ox=win.x, oy=win.y; const move=(ev)=>{ win.x=Math.max(0, Math.min(ox + (ev.clientX-startX), areaRect.width - rect.width)); win.y=Math.max(0, Math.min(oy + (ev.clientY-startY), areaRect.height - rect.height)); winEl.style.left=win.x+'px'; winEl.style.top=win.y+'px'; if(ev.clientY < areaRect.top + 12){ winEl.classList.add('snap-hint'); } else { winEl.classList.remove('snap-hint'); } }; const up=(ev)=>{ if(ev.clientY < areaRect.top + 12){ winEl.classList.remove('snap-hint'); toggleMaximizeOSApp(mode,id); } document.removeEventListener('mousemove',move);document.removeEventListener('mouseup',up);}; document.addEventListener('mousemove',move); document.addEventListener('mouseup',up); } }
    const resize=winEl.querySelector('[data-resize-handle]');
    if(resize){ resize.onmousedown=(e)=>{ e.stopPropagation(); const arr=getWindows(mode); const win=arr.find(w=>w.id===id); if(!win || win.maximized) return; const areaRect=workArea.getBoundingClientRect(); const startX=e.clientX, startY=e.clientY, ow=win.w, oh=win.h; const move=(ev)=>{ win.w=Math.max(380, Math.min(ow + (ev.clientX-startX), areaRect.width - win.x)); win.h=Math.max(240, Math.min(oh + (ev.clientY-startY), areaRect.height - win.y)); winEl.style.width=win.w+'px'; winEl.style.height=win.h+'px'; }; const up=()=>{document.removeEventListener('mousemove',move);document.removeEventListener('mouseup',up);}; document.addEventListener('mousemove',move); document.addEventListener('mouseup',up); } }
  });
}

function nav(items,active){
  sidebar.innerHTML=items.map(([id,icon,label])=>`<button class="nav-btn ${active===id?'active':''}" data-nav="${id}"><span class="icon">${icon}</span><span class="label-text">${esc(label)}</span></button>`).join('');
  sidebar.querySelectorAll('[data-nav]').forEach(b=>b.addEventListener('click',()=>setContext(b.dataset.nav,state.extra)));
}
function title(name,desc='',actions=''){return `<div class="page-title"><div><h1>${esc(name)}</h1><p>${desc}</p></div><div class="row">${actions}</div></div>`;}
function field(label,id,value='',type='text',extra=''){return `<div class="field"><label>${esc(label)}</label><input id="${id}" type="${type}" value="${esc(value??'')}" ${extra}></div>`;}
function commandValue(v,fallback=''){return Array.isArray(v)?v.join(', '):(v??fallback);}
function selectField(label,id,options,value){return `<div class="field"><label>${esc(label)}</label><select id="${id}">${options.map(([v,l])=>`<option value="${esc(v)}" ${String(v)===String(value)?'selected':''}>${esc(l)}</option>`).join('')}</select></div>`;}
function pageAdmin(){
  const bs=state.bootstrap||{};
  const fw=bs.framework||{};
  const resources=fw.resources||{};
  nav([['admin','⚙','Admin']],state.context);
  let html=title('Administracao Global FiveEMS','Somente configuracoes globais do script. Criacao de departamentos, cargos, frota, estoque e pontos ficam em paineis separados.');
  html+=`<div class="grid three"><div class="card"><div class="label">Framework</div><div class="stat" style="font-size:20px">${esc(fw.mode||'standalone')}</div><small>${fw.ready?'Integracao pronta':'Integracao incompleta'}</small></div><div class="card"><div class="label">Strict mode</div><div class="stat" style="font-size:20px">${fw.strict?'Ativo':'Desativado'}</div><small>FivePD SP Bridge</small></div><div class="card"><div class="label">Banco FiveEMS</div><div class="stat" style="font-size:20px">Auto</div><small>Migrations automaticas</small></div></div><div class="spacer"></div>`;
  html+=`<div class="grid two"><div class="card"><h3>Ocorrencias</h3>${field('Intervalo minimo (s)','callMin',bs.config?.calls?.minimumIntervalSeconds||300,'number')}${field('Intervalo maximo (s)','callMax',bs.config?.calls?.maximumIntervalSeconds||720,'number')}<button class="btn primary" id="saveCalls">Salvar ocorrencias</button></div><div class="card"><h3>Progressao global</h3>${field('XP por relatorio','xpReport',bs.config?.progression?.reportSubmitted||35,'number')}${field('XP por transferencia','xpHand',bs.config?.progression?.patientHandover||25,'number')}<button class="btn primary" id="saveXp">Salvar XP</button></div></div><div class="spacer"></div>`;
  html+=`<div class="card"><h3>Dano por categoria</h3><p class="label">Multiplicadores globais usados pela camada fisiologica do FiveEMS.</p><div class="grid four">${field('Tiro','dmgGun',bs.config?.damageMultipliers?.gunshot||1.35,'number','step="0.05"')}${field('Perfurocortante','dmgStab',bs.config?.damageMultipliers?.stabbing||1.2,'number','step="0.05"')}${field('Briga/contundente','dmgBlunt',bs.config?.damageMultipliers?.blunt||0.85,'number','step="0.05"')}${field('Veiculo','dmgVehicle',bs.config?.damageMultipliers?.vehicle||1.1,'number','step="0.05"')}${field('Queda','dmgFall',bs.config?.damageMultipliers?.fall||1,'number','step="0.05"')}${field('Explosao','dmgExplosion',bs.config?.damageMultipliers?.explosion||1.5,'number','step="0.05"')}${field('Queimadura','dmgBurn',bs.config?.damageMultipliers?.burn||0.8,'number','step="0.05"')}${field('Afogamento','dmgDrown',bs.config?.damageMultipliers?.drowning||1,'number','step="0.05"')}</div><button class="btn primary" id="saveDamage">Salvar dano</button></div><div class="spacer"></div>`;
  const npcCfg=bs.config?.npcPersistence||{};
  html+=`<div class="card"><div class="row between"><div><h3>Persistencia de pacientes NPC</h3><p class="label">Protege automaticamente NPCs feridos para que o GTA/FivePD SP nao os descarte enquanto o EMS busca maca ou viatura.</p></div><span class="pill">OneSync</span></div><div class="grid four">
    ${selectField('Ativo','npcPersistEnabled',[[true,'Sim'],[false,'Nao']],String(npcCfg.enabled!==false))}
    ${field('Raio de deteccao (m)','npcPersistRadius',npcCfg.scanRadius??70,'number','step="5"')}
    ${field('Persistencia (min)','npcPersistMinutes',npcCfg.persistMinutes??20,'number','step="1"')}
    ${field('Limite local','npcPersistMax',npcCfg.maxProtectedPerClient??24,'number','step="1"')}
  </div><button class="btn primary" id="saveNpcPersistence">Salvar persistencia NPC</button></div><div class="spacer"></div>`;

  const cmd=bs.config?.commands||{};
  html+=`<div class="card"><div class="row between"><div><h3>Comandos e numeros de emergencia</h3><p class="label">Use aliases separados por virgula. Exemplo Brasil: <b>192, 193</b>. Nao coloque a barra "/".</p></div><span class="pill">Personalizavel</span></div>
    <div class="grid two">
      <div class="card inset-card"><h3>Publico e operacao</h3>
        ${field('Chamado de emergencia','cmdEmergency',commandValue(cmd.emergency,'ems911'))}
        ${field('Ajuda','cmdHelp',commandValue(cmd.help,'fiveemshelp'))}
        ${field('Launcher EMS','cmdLauncher',commandValue(cmd.launcher,'fiveems'))}
        ${field('Atender proximo','cmdExam',commandValue(cmd.exam,'fiveemsexam'))}
        ${field('Paciente por ID','cmdPatient',commandValue(cmd.patient,'fiveemspatient'))}
        ${field('Monitor proximo','cmdMonitor',commandValue(cmd.monitor,'fiveemsmonitor'))}
      </div>
      <div class="card inset-card"><h3>Paineis / gestao</h3>
        ${field('Computador','cmdComputer',commandValue(cmd.computer,'fiveemscomputer'))}
        ${field('Tablet','cmdTablet',commandValue(cmd.tablet,'fiveemstablet'))}
        ${field('Mesa do Diretor','cmdDirector',commandValue(cmd.director,'fiveemsdirector'))}
        ${field('Painel Admin','cmdAdmin',commandValue(cmd.admin,'fiveemsadmin'))}
        ${field('Criador de Departamentos','cmdCreator',commandValue(cmd.creator,'fiveemscreator'))}
        <p class="label">Ferramentas internas de diagnostico continuam com nomes fixos e acesso somente Admin.</p>
      </div>
    </div><button class="btn primary" id="saveCommands">Salvar comandos</button></div><div class="spacer"></div>`;

  const stCfg=bs.config?.stretcher||{};
  const stHeight=stCfg.heightCalibration||{};
  const stPush=stCfg.pushOffset||{};
  const stPose=stCfg.patientPose||{};
  html+=`<div class="card"><div class="row between"><div><h3>Ajustes finos da maca</h3><p class="label">Calibracao global da StrykerPro. Os valores sao persistidos no banco e aplicados imediatamente a todos os players.</p></div><span class="pill">StrykerPro</span></div>
    <div class="grid two">
      <div class="card inset-card"><h3>Altura operacional</h3>
        ${field('Compensacao ALTA (m)','stHighLift',stHeight.highLift??0.465,'number','step="0.005"')}
        ${field('Compensacao BAIXA (m)','stLowLift',stHeight.lowLift??0.0,'number','step="0.005"')}
        <p class="label">Use passos pequenos, por exemplo 0.005 = 5 mm.</p>
      </div>
      <div class="card inset-card"><h3>Posicao ao conduzir</h3>
        <div class="grid three">
          ${field('X','stPushX',stPush.x??-0.05,'number','step="0.005"')}
          ${field('Y','stPushY',stPush.y??1.375,'number','step="0.005"')}
          ${field('Z','stPushZ',stPush.z??-0.345,'number','step="0.005"')}
        </div>
        <div class="grid three">
          ${field('Rot X','stPushRX',stPush.rx??180,'number','step="0.5"')}
          ${field('Rot Y','stPushRY',stPush.ry??180,'number','step="0.5"')}
          ${field('Rot Z','stPushRZ',stPush.rz??180,'number','step="0.5"')}
        </div>
      </div>
      <div class="card inset-card"><h3>Pose clínica na Stryker</h3>
        ${selectField('Calibrar fase automaticamente','stPoseAuto',[[true,'Sim'],[false,'Nao']],String(stPose.autoPhase!==false))}
        ${field('Fase manual (0.00–0.99)','stPosePhase',stPose.phase??0.46,'number','min="0" max="0.99" step="0.01"')}
        <p class="label">Auto procura o frame do <b>body_search</b> com pernas e braços mais estendidos para cada modelo de ped. A fase manual é o fallback/override.</p>
      </div>
    </div>
    <div class="row"><button class="btn primary" id="saveStretcherCalibration">Salvar e aplicar</button></div>
  </div><div class="spacer"></div>`;
  const rows=Object.entries(resources).map(([key,r])=>`<tr><td>${esc(key)}</td><td>${esc(r?.name||'---')}</td><td><span class="pill ${r?.state==='started'?'ok':'danger'}">${esc(r?.state||'missing')}</span></td></tr>`).join('');
  html+=`<div class="card"><div class="row between"><div><h3>Integracao FivePD SP</h3><p class="label">Estado dos resources usados pelo bridge.</p></div><button class="btn" id="refreshAdmin">Atualizar</button></div><div class="table-wrap"><table><thead><tr><th>Modulo</th><th>Resource</th><th>Status</th></tr></thead><tbody>${rows||'<tr><td colspan="3">Sem dados de framework.</td></tr>'}</tbody></table></div></div>`;
  content.innerHTML=html;
  saveCalls.onclick=()=>{nui('saveAdminSetting',{key:'calls',value:{minimumIntervalSeconds:n(callMin.value),maximumIntervalSeconds:n(callMax.value)}});toast('Configuracao de ocorrencias aplicada.');};
  saveXp.onclick=()=>{nui('saveAdminSetting',{key:'xp',value:{reportSubmitted:n(xpReport.value),patientHandover:n(xpHand.value)}});toast('Configuracao de XP aplicada.');};
  saveDamage.onclick=()=>{nui('saveAdminSetting',{key:'damageMultipliers',value:{gunshot:n(dmgGun.value),stabbing:n(dmgStab.value),blunt:n(dmgBlunt.value),vehicle:n(dmgVehicle.value),fall:n(dmgFall.value),explosion:n(dmgExplosion.value),burn:n(dmgBurn.value),drowning:n(dmgDrown.value)}});toast('Multiplicadores de dano aplicados.');};
  saveNpcPersistence.onclick=async()=>{
    const value={
      enabled:npcPersistEnabled.value==='true',
      scanRadius:n(npcPersistRadius.value,70),
      persistMinutes:n(npcPersistMinutes.value,20),
      maxProtectedPerClient:n(npcPersistMax.value,24)
    };
    await nui('saveAdminSetting',{key:'npcPersistence',value});
    if(state.bootstrap?.config) state.bootstrap.config.npcPersistence=value;
    toast('Persistencia de pacientes NPC salva.');
  };
  saveCommands.onclick=async()=>{
    const value={
      emergency:cmdEmergency.value, help:cmdHelp.value, launcher:cmdLauncher.value,
      computer:cmdComputer.value, tablet:cmdTablet.value, exam:cmdExam.value,
      patient:cmdPatient.value, monitor:cmdMonitor.value, director:cmdDirector.value,
      admin:cmdAdmin.value, creator:cmdCreator.value
    };
    await nui('saveAdminSetting',{key:'commands',value});
    if(state.bootstrap?.config) state.bootstrap.config.commands=value;
    toast('Comandos atualizados. Novos aliases ja estao ativos.');
  };
  saveStretcherCalibration.onclick=async()=>{
    const value={
      heightCalibration:{highLift:n(stHighLift.value),lowLift:n(stLowLift.value)},
      pushOffset:{
        x:n(stPushX.value),y:n(stPushY.value),z:n(stPushZ.value),
        rx:n(stPushRX.value),ry:n(stPushRY.value),rz:n(stPushRZ.value)
      },
      patientPose:{
        autoPhase:stPoseAuto.value==='true',
        phase:Math.max(0,Math.min(.99,n(stPosePhase.value,.46)))
      }
    };
    await nui('saveAdminSetting',{key:'stretcherCalibration',value});
    if(state.bootstrap?.config?.stretcher){
      state.bootstrap.config.stretcher.heightCalibration={...(state.bootstrap.config.stretcher.heightCalibration||{}),...value.heightCalibration};
      state.bootstrap.config.stretcher.pushOffset={...(state.bootstrap.config.stretcher.pushOffset||{}),...value.pushOffset};
      state.bootstrap.config.stretcher.patientPose={...(state.bootstrap.config.stretcher.patientPose||{}),...value.patientPose};
    }
    toast('Calibracao da maca salva e aplicada.');
  };
  refreshAdmin.onclick=()=>nui('requestBootstrap',{context:'admin'});
}

function pageDepartmentCreator(){
  const bs=state.bootstrap||{}; const d=state.department;
  const departments=bs.departments||[];
  const tabs=[['points','Pontos'],['garages','Garagens'],['ranks','Cargos'],['vehicles','Veiculos'],['vehiclekit','Equip. Viatura'],['supplies','Estoque'],['stretcher','Maca'],['care','Leitos/Outros']];
  let html=title('Criador de Departamentos','Crie o departamento primeiro; depois configure estrutura, cargos, frota, estoque, maca e destinos de paciente.');
  html+=`<div class="creator-layout"><aside class="creator-dept-sidebar"><div class="creator-side-head"><span class="section-kicker">Estrutura</span><h2>Departamentos</h2></div><button class="btn primary creator-new-btn" id="newDepartment">+ Criar novo</button><button class="creator-side-link ${state.creatorView==='list'?'active':''}" id="departmentListBtn">▦ Lista de departamentos</button><div class="creator-side-count">${departments.length} cadastrado(s)</div>${state.creatorView!=='list'&&d?`<div class="creator-current"><span class="label">Editando</span><b>${esc(d.name)}</b><small>${esc(d.type)}</small></div>`:''}</aside><section class="creator-main" id="creatorMain"></section></div>`;
  content.innerHTML=html;
  const main=document.getElementById('creatorMain');
  newDepartment.onclick=()=>{state.creatorCreating=true;pageDepartmentCreator();};
  departmentListBtn.onclick=()=>{state.creatorView='list';state.creatorSelectedId=null;pageDepartmentCreator();};

  if(state.creatorView==='list'){
    main.innerHTML=`<div class="creator-list-head"><div><span class="section-kicker">Departamentos</span><h2>Hospitais, EMS e Policia Cientifica</h2><p>Crie apenas nome e tipo. A configuracao completa fica disponivel depois.</p></div></div><div class="table-wrap creator-table"><table><thead><tr><th>Nome</th><th>Tipo</th><th>Status</th><th>Acoes</th></tr></thead><tbody>${departments.map(x=>{const configured=x.settings?.creator_configured===true;return `<tr><td><b>${esc(x.name)}</b><br><small>${esc(x.code||'')}</small></td><td><span class="pill">${esc(x.type)}</span></td><td>${configured?'<span class="pill ok">Configurado</span>':'<span class="pill warn">Pendente</span>'}</td><td><div class="row creator-actions"><button class="btn primary small" data-configure-dept="${x.id}" ${configured?'disabled':''}>Configurar</button><button class="btn small" data-edit-dept="${x.id}" ${configured?'':'disabled'}>Editar</button><button class="btn danger small" data-delete-dept="${x.id}" data-delete-name="${esc(x.name)}">Excluir</button></div></td></tr>`;}).join('')||'<tr><td colspan="4">Nenhum departamento criado.</td></tr>'}</tbody></table></div>`;
    main.querySelectorAll('[data-configure-dept]').forEach(b=>b.onclick=()=>{state.creatorSelectedId=Number(b.dataset.configureDept);state.creatorView='configure';state.creatorTab='points';nui('selectDepartment',{id:state.creatorSelectedId});});
    main.querySelectorAll('[data-edit-dept]').forEach(b=>b.onclick=()=>{state.creatorSelectedId=Number(b.dataset.editDept);state.creatorView='edit';state.creatorTab='points';nui('selectDepartment',{id:state.creatorSelectedId});});
    main.querySelectorAll('[data-delete-dept]').forEach(b=>b.onclick=()=>{
      const departmentId=Number(b.dataset.deleteDept);
      const departmentName=b.dataset.deleteName||'Departamento';
      const modal=document.createElement('div');
      modal.className='modal-backdrop';
      modal.innerHTML=`<div class="creator-modal">
        <div class="modal-head"><div><span class="section-kicker">Confirmar exclusao</span><h2>Excluir ${esc(departmentName)}?</h2></div><button class="modal-x" id="closeDeleteDepartment">×</button></div>
        <div class="creator-note danger-note"><b>Esta acao nao pode ser desfeita.</b><p>Pontos, cargos, frota, estoque, perfis de maca e configuracoes da viatura deste departamento serao removidos. Relatorios, atendimentos e casos historicos serao preservados, mas deixarao de apontar para o departamento excluido.</p></div>
        <div class="row end"><button class="btn" id="cancelDeleteDepartment">Cancelar</button><button class="btn danger" id="confirmDeleteDepartment">Excluir departamento</button></div>
      </div>`;
      content.appendChild(modal);
      const cancel=()=>modal.remove();
      modal.querySelector('#closeDeleteDepartment').onclick=cancel;
      modal.querySelector('#cancelDeleteDepartment').onclick=cancel;
      modal.querySelector('#confirmDeleteDepartment').onclick=()=>{
        const btn=modal.querySelector('#confirmDeleteDepartment');
        btn.disabled=true;btn.textContent='Excluindo...';
        nui('deleteDepartment',{departmentId});
        modal.remove();
        toast('Solicitando exclusao do departamento...');
      };
    });
  } else {
    if(!d || (state.creatorSelectedId && Number(d.id)!==Number(state.creatorSelectedId))){main.innerHTML='<div class="card">Carregando departamento...</div>';return;}
    const configured=d.settings?.creator_configured===true;
    main.innerHTML=`<div class="creator-config-head"><div><span class="section-kicker">${state.creatorView==='configure'?'Primeira configuracao':'Edicao'}</span><h2>${esc(d.name)}</h2><p>${esc(d.type)} · ${esc(d.code||'')}</p></div><button class="btn" id="backDepartments">← Departamentos</button></div>
      <div class="creator-general card"><div class="row between"><div><h3>Informacoes gerais e blip</h3><p class="label">Estas configuracoes ficam fora das abas operacionais.</p></div><span class="pill ${configured?'ok':'warn'}">${configured?'Configurado':'Pendente'}</span></div><div class="grid three">${field('Nome','deptName',d.name||'')}${field('Codigo','deptCode',d.code||'')}${selectField('Tipo','deptType',[['ems','EMS'],['hospital','Hospital'],['csi','Policia Cientifica / CSI']],d.type||'hospital')}</div><div class="grid three">${field('Blip sprite','blipSprite',d.settings?.blip?.sprite||61,'number')}${field('Blip cor','blipColor',d.settings?.blip?.color||2,'number')}${field('Escala','blipScale',d.settings?.blip?.scale||0.85,'number','step="0.05"')}</div><div class="row between"><label class="check"><input id="useCurrentBlip" type="checkbox"> Usar minha posicao atual como ponto do blip</label><button class="btn primary" id="saveGeneral">${state.creatorView==='configure'?'Concluir configuracao':'Salvar alteracoes'}</button></div></div>
      <div class="tabs creator-tabs">${tabs.map(([id,l])=>`<button class="tab ${state.creatorTab===id?'active':''}" data-ctab="${id}">${l}</button>`).join('')}</div><div id="creatorPane"></div>`;
    backDepartments.onclick=()=>{state.creatorView='list';state.creatorSelectedId=null;pageDepartmentCreator();};
    saveGeneral.onclick=()=>nui('saveDepartment',{id:d.id,name:deptName.value,code:deptCode.value,type:deptType.value,useCurrentBlip:useCurrentBlip.checked,markConfigured:true,settings:{...(d.settings||{}),creator_configured:true,blip:{sprite:n(blipSprite.value,61),color:n(blipColor.value,2),scale:n(blipScale.value,.85)}}});
    main.querySelectorAll('[data-ctab]').forEach(b=>b.onclick=()=>{state.creatorTab=b.dataset.ctab;pageDepartmentCreator();});
    const pane=document.getElementById('creatorPane');

    if(state.creatorTab==='points'){
      const operationalPointTypes=pointTypes.filter(([id])=>!['garage','bed','surgery','iml','other'].includes(id));
      pane.innerHTML=`<div class="grid two"><div class="card"><h3>Criar ponto operacional</h3>${selectField('Tipo','pointType',operationalPointTypes,'duty')}${field('Nome/label','pointLabel','')}<div class="creator-note"><b>Organizacao</b><p>Garagens sao cadastradas na aba <b>Garagens</b>. Leitos, cirurgia, IML e outros locais ficam em <b>Leitos/Outros</b>.</p></div><div class="spacer"></div><button class="btn primary" id="createPoint">Cadastrar posicao atual</button></div><div class="card"><h3>Pontos cadastrados</h3><div class="table-wrap"><table><thead><tr><th>Tipo</th><th>Label</th><th>XYZ</th><th></th></tr></thead><tbody>${(d.points||[]).filter(p=>!['garage','bed','surgery','iml','other'].includes(p.type)).map(p=>`<tr><td>${esc(p.type)}</td><td>${esc(p.label)}</td><td>${n(p.x).toFixed(1)}, ${n(p.y).toFixed(1)}, ${n(p.z).toFixed(1)}</td><td><button class="btn danger small" data-delpoint="${p.id}">Excluir</button></td></tr>`).join('')||'<tr><td colspan="4">Nenhum ponto operacional.</td></tr>'}</tbody></table></div></div></div>`;
      createPoint.onclick=()=>nui('savePointAtCurrent',{departmentId:d.id,point:{type:pointType.value,label:pointLabel.value}});
      pane.querySelectorAll('[data-delpoint]').forEach(b=>b.onclick=()=>nui('deletePoint',{departmentId:d.id,pointId:Number(b.dataset.delpoint)}));
    }

    if(state.creatorTab==='garages'){
      const garages=(d.points||[]).filter(p=>p.type==='garage');
      const selectedGarage=garages.find(g=>Number(g.id)===Number(state.creatorGarageSelectedId));
      if(!selectedGarage){
        pane.innerHTML=`<div class="creator-section"><div class="section-head"><div><div class="section-kicker">Garagens</div><h2>Pontos de garagem</h2><p>Cadastre a interacao, blip, categoria e depois posicione uma ou mais vagas com veiculo ghost + 3D Gizmo.</p></div><button class="btn primary" id="newGarage">+ Criar ponto de garagem</button></div><div class="table-wrap creator-table"><table><thead><tr><th>Nome</th><th>Tipo</th><th>Interacao</th><th>Status</th><th>Acoes</th></tr></thead><tbody>${garages.map(g=>{const gd=g.data||{};const configured=gd.garage_configured===true;const ik=gd.interaction?.kind||'marker';const interaction=ik==='ped'?'Ped/NPC':ik==='none'?'Sem interacao':'Marker';return `<tr><td><b>${esc(g.label||'Garagem')}</b><br><small>${n(g.x).toFixed(1)}, ${n(g.y).toFixed(1)}, ${n(g.z).toFixed(1)}</small></td><td><span class="pill">${esc(gd.garage_type||'car')}</span></td><td>${interaction}</td><td>${configured?'<span class="pill ok">Configurada</span>':'<span class="pill warn">Pendente</span>'}</td><td><div class="row creator-actions"><button class="btn primary small" data-config-garage="${g.id}" ${configured?'disabled':''}>Configurar</button><button class="btn small" data-edit-garage="${g.id}">Editar</button><button class="btn danger small" data-delete-garage="${g.id}">Excluir</button></div></td></tr>`;}).join('')||'<tr><td colspan="5">Nenhuma garagem cadastrada.</td></tr>'}</tbody></table></div></div>`;
        newGarage.onclick=()=>{state.creatorGarageCreating=true;pageDepartmentCreator();};
        pane.querySelectorAll('[data-config-garage]').forEach(b=>b.onclick=()=>{state.creatorGarageSelectedId=Number(b.dataset.configGarage);state.creatorGarageMode='configure';pageDepartmentCreator();});
        pane.querySelectorAll('[data-edit-garage]').forEach(b=>b.onclick=()=>{state.creatorGarageSelectedId=Number(b.dataset.editGarage);state.creatorGarageMode='edit';pageDepartmentCreator();});
        pane.querySelectorAll('[data-delete-garage]').forEach(b=>b.onclick=()=>{
          const pointId=Number(b.dataset.deleteGarage);
          const garage=garages.find(g=>Number(g.id)===pointId);
          const modal=document.createElement('div');
          modal.className='modal-backdrop';
          modal.innerHTML=`<div class="creator-modal"><div class="modal-head"><div><span class="section-kicker">Garagem</span><h2>Excluir ${esc(garage?.label||'esta garagem')}?</h2></div><button class="modal-x" id="closeGarageDelete">×</button></div><div class="creator-note danger-note"><b>Esta acao remove o ponto inteiro.</b><p>O NPC/Marker, vagas de spawn e configuracoes desta garagem serao removidos.</p></div><div class="modal-actions"><button class="btn" id="cancelGarageDelete">Cancelar</button><button class="btn danger" id="confirmGarageDelete">Excluir garagem</button></div></div>`;
          content.appendChild(modal);
          const cancel=()=>modal.remove();
          modal.querySelector('#closeGarageDelete').onclick=cancel;
          modal.querySelector('#cancelGarageDelete').onclick=cancel;
          modal.querySelector('#confirmGarageDelete').onclick=()=>{nui('deletePoint',{departmentId:d.id,pointId});modal.remove();toast('Garagem excluida.');};
        });
      } else {
        const gd=selectedGarage.data||{}; const spawns=gd.spawns||[]; const gt=gd.garage_type||'car'; const interaction=gd.interaction||{kind:'marker',marker_type:36,ped_model:'s_m_m_paramedic_01'}; const blip=gd.blip||{enabled:true,sprite:225,color:3,scale:.75}; const previewModel=gd.preview_model||garagePreviewModels[gt]||'ambulance';
        pane.innerHTML=`<div class="creator-section"><div class="section-head"><div><div class="section-kicker">${state.creatorGarageMode==='configure'?'Primeira configuracao':'Edicao'}</div><h2>${esc(selectedGarage.label||'Garagem')}</h2><p>Defina os dados da garagem e as vagas reais de spawn.</p></div><button class="btn" id="backGarageList">← Garagens</button></div><div class="grid two"><div class="card"><h3>Dados da garagem</h3>${field('Nome','garageEditName',selectedGarage.label||'Garagem')}${selectField('Tipo','garageEditType',garageTypes,gt)}${selectField('Interacao','garageEditInteraction',[['none','Sem interacao'],['marker','Marker'],['ped','Ped / NPC']],interaction.kind||'marker')}${selectField('Blip','garageEditBlip',garageBlips.map(x=>[x[0],`#${x[0]} · ${x[1]}`]),blip.sprite||225)}${selectField('Cor do blip','garageEditColor',garageColors.map(x=>[x[0],`#${x[0]} · ${x[1]}`]),blip.color||3)}${field('Escala do blip','garageEditScale',blip.scale||.75,'number','step="0.05"')}<div id="garageInteractionConfig"></div><label class="check"><input id="garageUseCurrent" type="checkbox"> Mover ponto da garagem para minha posicao atual</label><div class="spacer"></div><button class="btn primary" id="saveGarageInfo">Salvar dados</button></div><div class="card"><h3>Vagas de spawn</h3>${field('Modelo ghost para posicionar','garagePreviewModel',previewModel)}<p class="label">O veiculo fica transparente e sem colisao durante o 3D Gizmo.</p><button class="btn blue full-btn" id="addGarageSpawn">+ Adicionar vaga com 3D Gizmo</button><div class="spacer"></div><div class="garage-spawn-list">${spawns.map((s,i)=>`<div class="garage-spawn-row"><div><b>Vaga ${i+1}</b><small>${n(s.x).toFixed(2)}, ${n(s.y).toFixed(2)}, ${n(s.z).toFixed(2)} · H ${n(s.heading||s.rz).toFixed(1)}</small></div><div class="row"><button class="btn small blue" data-edit-gspawn="${i+1}">Editar Gizmo</button><button class="btn danger small" data-del-gspawn="${i+1}">Excluir</button></div></div>`).join('')||'<p>Nenhuma vaga configurada. Adicione pelo menos uma para concluir a garagem.</p>'}</div></div></div></div>`;
        const renderInteractionConfig=()=>{const kind=garageEditInteraction.value;const pt=interaction.ped_transform||null;
          if(kind==='ped'){
            garageInteractionConfig.innerHTML=`${selectField('Ped/NPC','garagePedModel',pedCatalog,interaction.ped_model||'s_m_m_paramedic_01')}<div class="catalog-preview ped-preview"><div class="ped-silhouette">♟</div><div><b>NPC da garagem</b><small id="pedPreviewLabel"></small></div></div><div class="row"><button class="btn blue" id="garagePedGizmo">3D Gizmo · Editar/Posicionar NPC</button><button class="btn danger" id="removeGarageInteraction">Excluir NPC</button></div><div class="transform-summary"><div><b>Posicao do NPC</b><small>${pt?`X ${n(pt.x).toFixed(2)} · Y ${n(pt.y).toFixed(2)} · Z ${n(pt.z).toFixed(2)}`:'Ainda nao posicionada pelo Gizmo'}</small></div></div>`;
            const pedSel=document.getElementById('garagePedModel');
            const update=()=>{const found=pedCatalog.find(x=>x[0]===pedSel.value);pedPreviewLabel.textContent=found?`${found[1]} · ${found[0]}`:pedSel.value;};
            pedSel.onchange=update;update();
            document.getElementById('garagePedGizmo').onclick=()=>nui('creatorGizmoGaragePed',{departmentId:d.id,pointId:selectedGarage.id,pedModel:pedSel.value});
          }else if(kind==='marker'){
            garageInteractionConfig.innerHTML=`${selectField('Marker','garageMarkerType',markerCatalog,interaction.marker_type||36)}<div class="catalog-preview marker-preview"><div class="marker-shape" id="markerPreviewShape"></div><div><b>Marker da garagem</b><small id="markerPreviewLabel"></small></div></div><div class="row"><span class="creator-note" style="flex:1"><b>Editar posicao</b><p>Marque "Mover ponto da garagem para minha posicao atual" abaixo e salve.</p></span><button class="btn danger" id="removeGarageInteraction">Excluir Marker</button></div>`;
            const markerSel=document.getElementById('garageMarkerType');
            const update=()=>{const found=markerCatalog.find(x=>String(x[0])===String(markerSel.value));markerPreviewLabel.textContent=found?`#${found[0]} · ${found[1]}`:`#${markerSel.value}`;markerPreviewShape.dataset.marker=markerSel.value;};
            markerSel.onchange=update;update();
          }else{
            garageInteractionConfig.innerHTML=`<div class="creator-note"><b>Sem interacao</b><p>Nenhum NPC ou Marker sera criado. Escolha Marker ou Ped/NPC acima quando quiser adicionar novamente.</p></div>`;
          }
          const remove=document.getElementById('removeGarageInteraction');
          if(remove)remove.onclick=()=>{garageEditInteraction.value='none';renderInteractionConfig();saveGarageInfo.click();};
        };
        renderInteractionConfig(); garageEditInteraction.onchange=renderInteractionConfig;
        backGarageList.onclick=()=>{state.creatorGarageSelectedId=null;state.creatorGarageMode='list';pageDepartmentCreator();};
        saveGarageInfo.onclick=()=>{const kind=garageEditInteraction.value;const nextInteraction={kind};if(kind==='marker'){nextInteraction.marker_type=n(document.getElementById('garageMarkerType')?.value,36);}else if(kind==='ped'){nextInteraction.ped_model=document.getElementById('garagePedModel')?.value||interaction.ped_model||'s_m_m_paramedic_01';if(interaction.ped_transform)nextInteraction.ped_transform={...interaction.ped_transform};}const updatedData={...gd,garage_type:garageEditType.value,preview_model:garagePreviewModel.value,blip:{enabled:true,sprite:n(garageEditBlip.value,225),color:n(garageEditColor.value,3),scale:n(garageEditScale.value,.75)},interaction:nextInteraction,spawns};nui('creatorSaveGarage',{departmentId:d.id,useCurrent:garageUseCurrent.checked,point:{...selectedGarage,label:garageEditName.value,type:'garage',data:updatedData}});};
        addGarageSpawn.onclick=()=>nui('creatorGizmoGarageSpawn',{departmentId:d.id,pointId:selectedGarage.id,previewModel:garagePreviewModel.value});
        pane.querySelectorAll('[data-edit-gspawn]').forEach(b=>b.onclick=()=>nui('creatorGizmoGarageSpawn',{departmentId:d.id,pointId:selectedGarage.id,spawnIndex:Number(b.dataset.editGspawn),previewModel:garagePreviewModel.value}));
        pane.querySelectorAll('[data-del-gspawn]').forEach(b=>b.onclick=()=>{
          const index=Number(b.dataset.delGspawn), expected=spawns[index-1];
          const modal=document.createElement('div');modal.className='garage-slot-modal';
          modal.innerHTML=`<div class="creator-modal" role="dialog" aria-modal="true" aria-labelledby="slotDeleteTitle"><div class="modal-head"><div><span class="section-kicker">${esc(selectedGarage.label||'Garagem')}</span><h2 id="slotDeleteTitle">Excluir vaga ${index}?</h2></div><button class="modal-x" data-cancel aria-label="Fechar">×</button></div><div class="creator-note"><p>Somente esta vaga sera removida. A garagem, as outras vagas e a frota serao mantidas.</p></div><p data-error role="alert"></p><div class="modal-actions"><button class="btn" data-cancel>Cancelar</button><button class="btn danger" data-confirm>Excluir vaga</button></div></div>`;
          frame.appendChild(modal);
          modal.querySelectorAll('[data-cancel]').forEach(button=>button.onclick=()=>modal.remove());
          const confirmButton=modal.querySelector('[data-confirm]');
          confirmButton.onclick=async()=>{
            confirmButton.disabled=true;confirmButton.textContent='Excluindo...';
            modal.querySelectorAll('[data-cancel]').forEach(button=>button.disabled=true);
            try{
              const result=await nui('creatorDeleteGarageSpawn',{departmentId:d.id,pointId:selectedGarage.id,spawnIndex:index,expected});
              if(!result?.ok)throw new Error(result?.message||'O servidor nao confirmou a exclusao.');
              modal.remove();toast('Vaga excluida.');
            }catch(error){
              modal.querySelector('[data-error]').textContent=error.message;
              confirmButton.disabled=false;confirmButton.textContent='Tentar novamente';
              modal.querySelectorAll('[data-cancel]').forEach(button=>button.disabled=false);
            }
          };
          modal.querySelector('[data-cancel]').focus();
        });
      }
    }
    if(state.creatorTab==='ranks'){
      pane.innerHTML=`<div class="grid two"><div class="card"><h3>Cargos existentes</h3>${(d.ranks||[]).map(r=>`<div class="rank-row"><span><b>${esc(r.name)}</b><br><small>Grade ${r.grade}</small></span><span class="pill">${(r.permissions||[]).length} permissoes</span></div>`).join('')||'<p>Nenhum cargo.</p>'}</div><div class="card"><h3>Novo cargo</h3>${field('Nome','rankName','')}${field('Grade','rankGrade',0,'number')}<div class="permission-grid">${permissionKeys.map(p=>`<label class="check"><input type="checkbox" data-perm="${p}"> ${p}</label>`).join('')}</div><div class="spacer"></div><button class="btn primary" id="saveRank">Criar cargo</button></div></div>`;
      saveRank.onclick=()=>nui('saveRank',{departmentId:d.id,rank:{name:rankName.value,grade:n(rankGrade.value),permissions:[...pane.querySelectorAll('[data-perm]:checked')].map(x=>x.dataset.perm)}});
    }
    if(state.creatorTab==='vehicles'){
      const vehicles=d.vehicles||[];
      const selected=vehicles.find(v=>Number(v.id)===Number(state.creatorVehicleSelectedId));
      pane.innerHTML=`<div class="grid two"><div class="card"><h3>Frota</h3><div class="table-wrap"><table><thead><tr><th>Nome</th><th>Model</th><th>Level</th><th>Acoes</th></tr></thead><tbody>${vehicles.map(v=>`<tr><td>${esc(v.label)}</td><td>${esc(v.model)}</td><td>${n(v.min_level,1)}</td><td><button class="btn small" data-edit-vehicle="${v.id}">Editar</button> <button class="btn danger small" data-delete-vehicle="${v.id}">Remover</button></td></tr>`).join('')||'<tr><td colspan="4">Nenhuma viatura cadastrada.</td></tr>'}</tbody></table></div></div><div class="card"><h3>${selected?'Editar viatura':'Cadastrar veiculo / aeronave'}</h3>${field('Nome exibido','vehicleLabel',selected?.label||'Ambulancia')}${field('Spawn model','vehicleModel',selected?.model||'ambulance')}${field('Level minimo','vehicleLevel',selected?.min_level||1,'number','min="1" step="1"')}<button class="btn primary" id="saveVehicle">Salvar</button> <button class="btn" id="newVehicle">${selected?'Cancelar edicao':'Novo veiculo'}</button><div class="creator-note"><b>Maca</b><p>A Stryker Pro permanece fixa na garagem; os encaixes ficam na aba <b>Maca</b>.</p></div></div></div>`;
      newVehicle.onclick=()=>{state.creatorVehicleSelectedId=null;pageDepartmentCreator();};
      pane.querySelectorAll('[data-edit-vehicle]').forEach(b=>b.onclick=()=>{state.creatorVehicleSelectedId=Number(b.dataset.editVehicle);pageDepartmentCreator();});
      pane.querySelectorAll('[data-delete-vehicle]').forEach(b=>b.onclick=()=>{
        const vehicle=vehicles.find(v=>Number(v.id)===Number(b.dataset.deleteVehicle));
        const modal=document.createElement('div');modal.className='modal-backdrop';
        modal.innerHTML=`<div class="creator-modal"><div class="modal-head"><h2>Remover ${esc(vehicle.label)} da frota?</h2></div><p>A viatura deixara de aparecer no catalogo da garagem. Os perfis de maca e equipamentos serao preservados.</p><div class="modal-actions"><button class="btn" data-cancel>Cancelar</button><button class="btn danger" data-confirm>Remover</button></div></div>`;
        content.appendChild(modal);
        modal.querySelector('[data-cancel]').onclick=()=>modal.remove();
        modal.querySelector('[data-confirm]').onclick=()=>{nui('deleteVehicle',{departmentId:d.id,vehicleId:Number(vehicle.id)});state.creatorVehicleSelectedId=null;modal.remove();};
      });
      saveVehicle.onclick=()=>{
        const label=vehicleLabel.value.trim(), model=vehicleModel.value.trim();
        if(!label||!model)return toast('Informe nome e modelo da viatura.');
        let settings=selected?.settings||{};
        if(typeof settings==='string'){try{settings=JSON.parse(settings);}catch{return toast('Configuracao da viatura invalida.');}}
        nui('saveVehicle',{departmentId:d.id,vehicle:{id:selected?.id,label,model,min_level:Math.max(1,Math.floor(n(vehicleLevel.value,1))),settings}});
      };
    }
    if(state.creatorTab==='vehiclekit'){
      const profiles=d.vehicleEquipmentProfiles||[];
      const models=(d.vehicles||[]).map(v=>v.model).filter(Boolean);
      const selectedModel=state.creatorVehicleEquipmentModel||profiles[0]?.vehicle_model||models[0]||'ambulance';
      const selected=profiles.find(p=>String(p.vehicle_model)===String(selectedModel))||null;
      const raw=selected?.transform||{x:0,y:-2.5,z:.8,rx:0,ry:0,rz:0};
      const legacy={x:n(raw.x,0),y:n(raw.y,-2.5),z:n(raw.z,.8),rx:n(raw.rx,0),ry:n(raw.ry,0),rz:n(raw.rz??raw.heading,0)};
      const compartment=raw.compartment||legacy;
      const bagMount=raw.bag||raw.bag_mount||compartment;
      const zoneSize=raw.zone?.size||raw.size||{x:1.2,y:1.0,z:1.1};
      const layoutTransform={...raw,compartment:{...compartment},bag:{...bagMount},zone:{...(raw.zone||{}),size:{x:n(zoneSize.x,1.2),y:n(zoneSize.y,1.0),z:n(zoneSize.z,1.1)}}};
      pane.innerHTML=`<div class="creator-section"><div class="section-head"><div><div class="section-kicker">Compartimento EMS + Bolsa física</div><h2>Equipamentos da viatura</h2><p>O compartimento usa uma <b>área 3D</b> sem prop de referência. A bolsa médica possui um suporte próprio e aparece fisicamente dentro da viatura.</p></div><span class="pill">${profiles.length} configurado(s)</span></div><div class="grid two"><div class="card"><h3>Viatura selecionada</h3>${models.length?selectField('Spawn model','vehKitModel',models.map(m=>[m,m]),selectedModel):field('Spawn model','vehKitModel',selectedModel)}<div class="creator-note blue-note"><b>Área do Compartimento EMS</b><p>Posicione o centro da área de interação. Ela acompanha a viatura e não depende da bolsa para o ox_target.</p></div><button class="btn primary full-btn" id="vehKitZoneGizmo">3D Gizmo · Centro da área</button><div class="grid three">${field('Largura X','vehZoneX',n(zoneSize.x,1.2),'number','step="0.05" min="0.25"')}${field('Profundidade Y','vehZoneY',n(zoneSize.y,1.0),'number','step="0.05" min="0.25"')}${field('Altura Z','vehZoneZ',n(zoneSize.z,1.1),'number','step="0.05" min="0.25"')}</div><button class="btn full-btn" id="vehKitSaveZone">Salvar dimensões da área</button><div class="transform-summary"><div><b>Centro do compartimento</b><small>X ${n(compartment.x).toFixed(2)} · Y ${n(compartment.y).toFixed(2)} · Z ${n(compartment.z).toFixed(2)}</small></div></div><div class="spacer"></div><div class="creator-note blue-note"><b>Bolsa médica na viatura</b><p>Use o prop real para escolher onde a bolsa ficará visível quando estiver guardada.</p></div><button class="btn blue full-btn" id="vehBagGizmo">3D Gizmo · Posição da bolsa</button><div class="transform-summary"><div><b>Suporte da bolsa</b><small>X ${n(bagMount.x).toFixed(2)} · Y ${n(bagMount.y).toFixed(2)} · Z ${n(bagMount.z).toFixed(2)}</small></div></div></div><div class="card"><h3>Perfis cadastrados</h3>${profiles.map(p=>`<button class="profile-row ${String(p.vehicle_model)===String(selectedModel)?'active':''}" data-vehkit-profile="${esc(p.vehicle_model)}"><span><b>${esc(p.vehicle_model)}</b><small>Área + bolsa física</small></span><span>Editar →</span></button>`).join('')||'<p>Nenhum compartimento configurado.</p>'}<div class="creator-note"><b>Uso em jogo</b><p>Mire na <b>bolsa visível</b> para retirá-la. Depois de retirada, mire no suporte vazio para <b>guardar a bolsa</b>. O restante dos itens usa somente a área do <b>Compartimento EMS</b>.</p></div></div></div></div>`;
      const currentLayout=()=>({...layoutTransform,zone:{...(layoutTransform.zone||{}),size:{x:n(vehZoneX.value,1.2),y:n(vehZoneY.value,1.0),z:n(vehZoneZ.value,1.1)}}});
      pane.querySelectorAll('[data-vehkit-profile]').forEach(b=>b.onclick=()=>{state.creatorVehicleEquipmentModel=b.dataset.vehkitProfile;pageDepartmentCreator();});
      vehKitModel.onchange=()=>{state.creatorVehicleEquipmentModel=vehKitModel.value;pageDepartmentCreator();};
      vehKitZoneGizmo.onclick=()=>nui('creatorGizmoVehicleEquipment',{departmentId:d.id,vehicleModel:vehKitModel.value,transform:currentLayout(),mode:'compartment'});
      vehBagGizmo.onclick=()=>nui('creatorGizmoVehicleEquipment',{departmentId:d.id,vehicleModel:vehKitModel.value,transform:currentLayout(),mode:'bag'});
      vehKitSaveZone.onclick=()=>nui('creatorSaveVehicleEquipmentLayout',{departmentId:d.id,vehicleModel:vehKitModel.value,transform:currentLayout()});
    }
    if(state.creatorTab==='supplies'){
      pane.innerHTML=`<div class="row between"><div><b>Estoque do departamento</b><div class="label">O catalogo e inserido automaticamente ao criar o departamento.</div></div><button class="btn primary" id="seed">Recarregar catalogo padrao</button></div><div class="spacer"></div><div class="table-wrap"><table><thead><tr><th>Item</th><th>Categoria</th><th>Quantidade</th><th>Level</th></tr></thead><tbody>${(d.supplies||[]).map(s=>`<tr><td>${esc(s.label)}<br><small>${esc(s.item_name)}</small></td><td>${esc(s.category)}</td><td>${s.quantity}</td><td>${s.min_level}</td></tr>`).join('')}</tbody></table></div>`;
      seed.onclick=()=>nui('seedSupplies',{departmentId:d.id});
    }
    if(state.creatorTab==='stretcher'){
      const profiles=d.stretcherProfiles||[];
      let selected=profiles.find(p=>String(p.vehicle_model)===String(state.creatorStretcherVehicle)); selected=selected||profiles[0]||null;
      const inside=selected?.inside_transform||{x:0,y:-2,z:0.2,rx:0,ry:0,rz:0};
      const outside=selected?.outside_transform||{x:0,y:-3.2,z:0,rx:0,ry:0,rz:0};
      const patient=selected?.patient_transform||{x:0,y:0.08,z:1.12,rx:0,ry:0,rz:180};
      pane.innerHTML=`<div class="creator-section"><div class="section-head"><div><div class="section-kicker">Stryker Pro / Transporte</div><h2>Perfil por ambulancia ou aeronave</h2><p>Cada modelo possui configuracao propria de encaixe. A maca de preview aparece <b>sem equipamentos e com encosto abaixado</b>.</p></div><span class="pill">${profiles.length} perfil(is)</span></div><div class="grid two"><div class="card"><h3>Perfil selecionado</h3>${field('Model da ambulancia/aeronave','stVeh',selected?.vehicle_model||'ambulance')}${field('Model da maca','stModel',selected?.stretcher_model||d?.settings?.defaultStretcherModel||state.bootstrap?.config?.stretcher?.defaultModel||'strykerpro')}<div class="stretcher-config-group"><div><span class="section-kicker">Maca na ambulancia</span><h3>Posicionamento da maca</h3><p class="label">Use estes botoes para mover a <b>maca</b>, nunca o paciente.</p></div><div class="gizmo-actions two-actions"><button class="btn blue" id="gizmoInside">3D Gizmo · Maca dentro</button><button class="btn blue" id="gizmoOutside">3D Gizmo · Maca fora</button></div></div><div class="stretcher-config-group patient-group"><div><span class="section-kicker">Paciente na maca</span><h3>Player / NPC</h3><p class="label">Este e o unico editor que cria o NPC de preview sobre a maca.</p></div><button class="btn primary full-btn" id="gizmoPatient">3D Gizmo · Posicionar paciente na maca</button></div><div class="transform-summary"><div><b>Maca dentro</b><small>X ${n(inside.x).toFixed(2)} · Y ${n(inside.y).toFixed(2)} · Z ${n(inside.z).toFixed(2)}</small></div><div><b>Maca fora</b><small>X ${n(outside.x).toFixed(2)} · Y ${n(outside.y).toFixed(2)} · Z ${n(outside.z).toFixed(2)}</small></div><div><b>Paciente</b><small>X ${n(patient.x).toFixed(2)} · Y ${n(patient.y).toFixed(2)} · Z ${n(patient.z).toFixed(2)}</small></div></div><div class="spacer"></div><button class="btn" id="saveSt">Salvar perfil</button></div><div class="card"><h3>Perfis cadastrados</h3>${profiles.map(p=>`<button class="profile-row ${selected&&String(selected.vehicle_model)===String(p.vehicle_model)?'active':''}" data-load-stprofile="${esc(p.vehicle_model)}"><span><b>${esc(p.vehicle_model)}</b><small>${esc(p.stretcher_model)}</small></span><span>Editar →</span></button>`).join('')||'<p>Nenhum perfil salvo.</p>'}<div class="creator-note"><b>Fluxo automatico</b><p>Ao carregar, a maca usa <b>Maca dentro</b> e entra baixa. Ao descarregar, usa <b>Maca fora</b> e sai alta/afastada.</p></div><div class="creator-note blue-note"><b>Importante</b><p>Ambulancias e aeronaves podem ter interiores diferentes. Salve um perfil separado para cada spawn model.</p></div></div></div></div><div class="creator-section gizmo-help"><div class="section-kicker">Controles do 3D Gizmo</div><div class="gizmo-key-grid"><span><kbd>Setas</kbd> mover</span><span><kbd>PgUp/PgDn</kbd> subir/descer</span><span><kbd>Q/E</kbd> girar</span><span><kbd>G</kbd> modo mover</span><span><kbd>R</kbd> gizmo rotacao</span><span><kbd>L</kbd> local/world</span><span><kbd>Mouse Esq.</kbd> arrastar eixo</span><span><kbd>ENTER</kbd> salvar</span><span><kbd>BACKSPACE</kbd> cancelar</span></div></div>`;
      const profilePayload=()=>({vehicle_model:stVeh.value,stretcher_model:stModel.value||'strykerpro',inside_transform:inside,outside_transform:outside,patient_transform:patient});
      pane.querySelectorAll('[data-load-stprofile]').forEach(b=>b.onclick=()=>{state.creatorStretcherVehicle=b.dataset.loadStprofile;pageDepartmentCreator();});
      saveSt.onclick=()=>nui('saveStretcherProfile',{departmentId:d.id,profile:profilePayload()});
      gizmoInside.onclick=()=>nui('creatorGizmoStretcher',{departmentId:d.id,mode:'inside',profile:profilePayload()});
      gizmoOutside.onclick=()=>nui('creatorGizmoStretcher',{departmentId:d.id,mode:'outside',profile:profilePayload()});
      gizmoPatient.onclick=()=>nui('creatorGizmoStretcher',{departmentId:d.id,mode:'patient',profile:profilePayload()});
    }
    if(state.creatorTab==='care'){
      const carePoints=(d.points||[]).filter(p=>['bed','surgery','iml','other'].includes(p.type));
      const typeLabel={bed:'Leito',surgery:'Mesa de cirurgia',iml:'IML',other:'Outro'};
      pane.innerHTML=`<div class="creator-section"><div class="section-head"><div><div class="section-kicker">Leitos / Outros</div><h2>Destinos do paciente</h2><p>Cadastre o local e depois posicione um NPC de preview exatamente onde Player/NPC deve ficar.</p></div><button class="btn primary" id="newCarePoint">+ Cadastrar leito/outro</button></div><div class="care-grid">${carePoints.map(p=>{const pt=p.data?.patient_transform||{};return `<div class="care-card"><div><span class="pill">${esc(typeLabel[p.type]||p.type)}</span><h3>${esc(p.label||p.type)}</h3><small>Ancora: ${n(p.x).toFixed(2)}, ${n(p.y).toFixed(2)}, ${n(p.z).toFixed(2)}</small><p>Paciente: X ${n(pt.x).toFixed(2)} · Y ${n(pt.y).toFixed(2)} · Z ${n(pt.z,.90).toFixed(2)}</p></div><div class="row"><button class="btn blue" data-care-gizmo="${p.id}">Reposicionar NPC</button><button class="btn danger small" data-care-delete="${p.id}">Excluir</button></div></div>`;}).join('')||'<div class="card"><p>Nenhum leito/outro cadastrado.</p></div>'}</div></div><div class="creator-note"><b>Como cadastrar</b><p>Fique ao lado do leito/mesa/local, clique em cadastrar, informe nome e tipo. O FiveEMS salva a ancora na sua posicao e abre o 3D Gizmo com um NPC de preview para voce posicionar o corpo.</p></div>`;
      newCarePoint.onclick=()=>{state.creatorCareCreating=true;pageDepartmentCreator();};
      pane.querySelectorAll('[data-care-gizmo]').forEach(b=>b.onclick=()=>nui('creatorGizmoCarePoint',{departmentId:d.id,pointId:Number(b.dataset.careGizmo)}));
      pane.querySelectorAll('[data-care-delete]').forEach(b=>b.onclick=()=>{if(confirm('Excluir este leito/outro?'))nui('deletePoint',{departmentId:d.id,pointId:Number(b.dataset.careDelete)});});
    }
  }

  if(state.creatorCreating){
    const modal=document.createElement('div'); modal.className='modal-backdrop';
    modal.innerHTML=`<div class="creator-modal"><div class="modal-head"><div><span class="section-kicker">Novo departamento</span><h2>Criar departamento</h2></div><button class="modal-x" id="closeCreateDept">×</button></div>${field('Nome','newDeptName','')}${selectField('Tipo','newDeptType',[['hospital','Hospital'],['ems','EMS'],['csi','Policia Cientifica / CSI']],'hospital')}<div class="modal-actions"><button class="btn" id="cancelCreateDept">Cancelar</button><button class="btn primary" id="confirmCreateDept">Criar</button></div></div>`;
    content.appendChild(modal);
    const cancel=()=>{state.creatorCreating=false;pageDepartmentCreator();};
    closeCreateDept.onclick=cancel;cancelCreateDept.onclick=cancel;
    confirmCreateDept.onclick=()=>{const name=newDeptName.value.trim();if(!name)return toast('Informe o nome do departamento.');state.creatorCreating=false;state.creatorView='list';nui('saveDepartment',{name,type:newDeptType.value,createOnly:true,settings:{creator_configured:false,defaultStretcherModel:'strykerpro',blip:{sprite:61,color:2,scale:.85}}});};
  }


  if(state.creatorGarageCreating && d){
    const modal=document.createElement('div'); modal.className='modal-backdrop';
    modal.innerHTML=`<div class="creator-modal garage-modal"><div class="modal-head"><div><span class="section-kicker">Nova garagem</span><h2>Criar ponto de garagem</h2></div><button class="modal-x" id="closeGarageModal">×</button></div>${field('Nome','newGarageName','Garagem Principal')}${selectField('Tipo de garagem','newGarageType',garageTypes,'car')}${selectField('Blip nativo','newGarageBlip',garageBlips.map(x=>[x[0],`#${x[0]} · ${x[1]}`]),225)}${selectField('Cor do blip','newGarageColor',garageColors.map(x=>[x[0],`#${x[0]} · ${x[1]}`]),3)}${selectField('Interacao','newGarageInteraction',[['marker','Marker'],['ped','Ped / NPC']],'marker')}<div id="newGarageInteractionConfig"></div><div class="garage-catalog-preview"><div class="catalog-preview blip-preview"><div class="blip-dot">●</div><div><b>Blip</b><small id="newBlipPreview"></small></div></div><div class="catalog-preview type-preview"><div class="garage-type-icon" id="garageTypeIcon">🚑</div><div><b>Tipo</b><small id="garageTypePreview"></small></div></div></div><div class="creator-note"><b>Posicao do ponto</b><p>O Marker usa sua posicao atual. Se escolher <b>Ped / NPC</b>, ao confirmar o FiveEMS fecha o painel e abre automaticamente o <b>3D Gizmo</b> para voce colocar o atendente exatamente no chao e na orientacao desejada.</p></div><div class="modal-actions"><button class="btn" id="cancelGarageModal">Cancelar</button><button class="btn primary" id="confirmGarageModal">Confirmar</button></div></div>`;
    content.appendChild(modal);
    const renderNewInteraction=()=>{const kind=newGarageInteraction.value;newGarageInteractionConfig.innerHTML=kind==='ped'?`${selectField('Ped/NPC','newGaragePed',pedCatalog,'s_m_m_paramedic_01')}<div class="catalog-preview ped-preview"><div class="ped-silhouette">♟</div><div><b>Preview NPC</b><small id="newPedPreview"></small></div></div>`:`${selectField('Marker','newGarageMarker',markerCatalog,36)}<div class="catalog-preview marker-preview"><div class="marker-shape" id="newMarkerShape"></div><div><b>Preview Marker</b><small id="newMarkerPreview"></small></div></div>`;const psel=document.getElementById('newGaragePed');const msel=document.getElementById('newGarageMarker');if(psel){const u=()=>{const f=pedCatalog.find(x=>x[0]===psel.value);newPedPreview.textContent=f?`${f[1]} · ${f[0]}`:psel.value;};psel.onchange=u;u();}if(msel){const u=()=>{const f=markerCatalog.find(x=>String(x[0])===String(msel.value));newMarkerPreview.textContent=f?`#${f[0]} · ${f[1]}`:`#${msel.value}`;newMarkerShape.dataset.marker=msel.value;};msel.onchange=u;u();}};
    const updateGaragePreview=()=>{const f=garageTypes.find(x=>x[0]===newGarageType.value);garageTypePreview.textContent=f?f[1]:newGarageType.value;garageTypeIcon.textContent={car:'🚑',motorcycle:'🏍',aircraft:'🚁',boat:'🚤',truck:'🚚',bus:'🚌'}[newGarageType.value]||'🚗';const b=garageBlips.find(x=>String(x[0])===String(newGarageBlip.value));newBlipPreview.textContent=b?`#${b[0]} · ${b[1]}`:`#${newGarageBlip.value}`;};
    renderNewInteraction();updateGaragePreview();newGarageInteraction.onchange=renderNewInteraction;newGarageType.onchange=updateGaragePreview;newGarageBlip.onchange=updateGaragePreview;
    const cancel=()=>{state.creatorGarageCreating=false;pageDepartmentCreator();};closeGarageModal.onclick=cancel;cancelGarageModal.onclick=cancel;
    confirmGarageModal.onclick=()=>{const label=newGarageName.value.trim();if(!label)return toast('Informe o nome da garagem.');const gt=newGarageType.value;const kind=newGarageInteraction.value;const data={garage_configured:false,garage_type:gt,preview_model:garagePreviewModels[gt]||'ambulance',blip:{enabled:true,sprite:n(newGarageBlip.value,225),color:n(newGarageColor.value,3),scale:.75},interaction:{kind,marker_type:kind==='marker'?n(document.getElementById('newGarageMarker')?.value,36):36,ped_model:kind==='ped'?(document.getElementById('newGaragePed')?.value||'s_m_m_paramedic_01'):'s_m_m_paramedic_01'},spawns:[]};state.creatorGarageCreating=false;nui('creatorCreateGarage',{departmentId:d.id,label,data});};
  }

  if(state.creatorCareCreating && d){
    const modal=document.createElement('div'); modal.className='modal-backdrop';
    modal.innerHTML=`<div class="creator-modal"><div class="modal-head"><div><span class="section-kicker">Leitos / Outros</span><h2>Cadastrar destino</h2></div><button class="modal-x" id="closeCareModal">×</button></div>${field('Nome do leito/local','careName','Leito 01')}${selectField('Tipo','careType',[['bed','Leito'],['surgery','Mesa de cirurgia'],['iml','IML / mesa mortuaria'],['other','Outro local']],'bed')}<div class="creator-note"><b>Posicao inicial</b><p>A ancora sera criada na sua posicao atual. Em seguida o painel fecha e um NPC de preview aparece para voce posicionar com o 3D Gizmo.</p></div><div class="modal-actions"><button class="btn" id="cancelCareModal">Cancelar</button><button class="btn primary" id="confirmCareModal">Criar e posicionar NPC</button></div></div>`;
    content.appendChild(modal);
    const cancel=()=>{state.creatorCareCreating=false;pageDepartmentCreator();};
    closeCareModal.onclick=cancel;cancelCareModal.onclick=cancel;
    confirmCareModal.onclick=()=>{const label=careName.value.trim();if(!label)return toast('Informe o nome do leito/local.');state.creatorCareCreating=false;nui('creatorCreateCarePoint',{departmentId:d.id,label,type:careType.value});};
  }
}
function pageOS(){
  nav([['os','⌂','Launcher'],['computer','🖥','Computador'],['tablet','▤','Tablet'],['director','♜','Mesa do diretor'],['monitor','♥','Monitor'],['patient','✚','Paciente'],['csi','⌕','CSI']],state.context);
  const member=state.bootstrap?.member;
  content.innerHTML=`<div class="fiveems-brand-hero"><img src="assets/fiveems-banner.png" alt="FiveEMS"><div class="fiveems-brand-hero-shade"></div><div class="fiveems-brand-hero-copy"><img src="assets/fiveems-wordmark.png" alt="FiveEMS"><span>MEDICAL • EMS • HOSPITAL OPERATIONS</span></div></div>`+title('FiveEMS Launcher','Arquitetura separada: Admin, Mesa do Diretor, Computer Medical OS, Tablet Medical OS e Monitor multiparamétrico.',member?`<span class="pill ${member.on_duty?'ok':''}">${member.on_duty?'Em servico':'Fora de servico'}</span>`:'')+`
  <div class="grid four"><div class="card"><div class="label">Profissional</div><div class="stat">${esc(member?.display_name||'---')}</div><small>${esc(member?.rank_name||'Sem cargo')}</small></div><div class="card"><div class="label">Level</div><div class="stat">${member?.level||1}</div><small>${member?.xp||0} XP</small></div><div class="card"><div class="label">Departamento</div><div class="stat" style="font-size:18px">${esc(member?.department_name||'Nao atribuido')}</div></div><div class="card"><div class="label">Status</div><div class="stat" style="font-size:18px">FiveEMS v${esc(state.bootstrap?.resourceVersion||'dev')}</div></div></div>
  <div class="spacer"></div>
  <div class="launcher-grid">${(()=>{const apps=[
    ['computer','🖥','Computer Medical OS','Desktop clinico com os softwares operacionais do hospital e do EMS.'],
    ['tablet','▤','Tablet Medical OS','Versao touch com os mesmos softwares do computador, mas em layout proprio.'],
    ['director','♜','Mesa do Diretor','Gestao interna do departamento para cargos autorizados.'],
    ['monitor','♥','Monitor Multiparametrico','Aparelho separado. So mostra sinais quando conectado a um paciente.'],
    ['patient','✚','Atendimento ao Paciente','Triagem, XABCDE, tratamentos, oxigenio e relatorio.']
  ]; if(state.bootstrap?.isAdmin){apps.push(['creator','✥','Criador de Departamentos','Criacao e estrutura fisica de Hospital, EMS e Policia Cientifica.']);apps.push(['admin','⚙','Painel de Admin','Somente configuracoes globais, integracao e diagnostico do FiveEMS.']);} return apps;})().map(([id,g,t,d])=>`<button class="launcher-card" data-launch="${id}"><span class="lglyph">${g}</span><span><h3>${t}</h3><p>${d}</p><span class="pill">Abrir</span></span></button>`).join('')}</div>`;
  content.querySelectorAll('[data-launch]').forEach(b=>b.onclick=()=>setContext(b.dataset.launch,{}));
}

function vitalsBlock(v={}){return `<div class="vitals"><div class="vital"><small>FC</small><strong>${n(v.hr,'--')}</strong></div><div class="vital"><small>FR</small><strong>${n(v.rr,'--')}</strong></div><div class="vital"><small>PA</small><strong style="font-size:22px">${n(v.sys,'--')}/${n(v.dia,'--')}</strong></div><div class="vital"><small>SpO₂</small><strong>${n(v.spo2,'--')}%</strong></div><div class="vital"><small>Temp</small><strong>${n(v.temp,0).toFixed(1)}</strong></div><div class="vital"><small>GCS</small><strong>${n(v.gcs,'--')}</strong></div></div>`;}

function formatClinicalTime(ts){
  if(!ts)return '--';
  const d=new Date(Number(ts)*1000);
  return Number.isNaN(d.getTime())?'--':d.toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'});
}

function injurySeverityClass(v){v=n(v);return v>=70?'critical':v>=40?'moderate':v>0?'minor':'clear';}
function itemLabel(key){
  const all=[...(state.bootstrap?.catalog?.equipment||[]),...(state.bootstrap?.catalog?.medications||[])];
  return all.find(x=>x.name===key)?.label||String(key||'');
}
function clinicalBagCount(item){return n((state.medicalBag||state.bootstrap?.medicalBag||{})[item]);}
function observedValue(s,key){
  const o=s?.observedVitals||{};
  for(const v of Object.values(o)){ if(v&&Object.prototype.hasOwnProperty.call(v,key)) return v[key]; }
  return null;
}

const clinicalSceneTreatmentByItem={
  pressure_bandage:'pressure_bandage',wound_pack:'wound_pack',tourniquet:'tourniquet',chest_seal:'chest_seal',
  c_collar:'c_collar',splint:'splint',opa:'airway_opa',suction_kit:'suction',iv_kit:'iv_access',
  thermal_blanket:'thermal_blanket',burn_dressing:'burn_dressing'
};
const clinicalSceneMeasurementByItem={stethoscope:'auscultation',bp_cuff:'blood_pressure',pulse_oximeter:'spo2',thermometer:'temperature'};
const clinicalSceneCategoryLabels={assessment:'AVALIAÇÃO',bleeding:'HEMORRAGIA',respiratory:'RESPIRATÓRIO',immobilization:'IMOBILIZAÇÃO',airway:'VIA AÉREA',oxygen:'OXIGÊNIO',circulation:'CIRCULAÇÃO',exposure:'EXPOSIÇÃO',burn:'QUEIMADURA',cardiac:'CARDÍACO'};

function sceneCatalogItem(key){
  const eq=state.bootstrap?.catalog?.equipment||state.bootstrap?.equipment||[];
  return Array.isArray(eq)?eq.find(x=>x.name===key):null;
}
function sceneItemCategory(key){return sceneCatalogItem(key)?.category||({stethoscope:'assessment',bp_cuff:'assessment',pulse_oximeter:'assessment',thermometer:'assessment',pressure_bandage:'bleeding',wound_pack:'bleeding',tourniquet:'bleeding',chest_seal:'respiratory',c_collar:'immobilization',splint:'immobilization',opa:'airway',suction_kit:'airway',iv_kit:'circulation',thermal_blanket:'exposure',burn_dressing:'burn'})[key]||'treatment';}
function knownClinicalFindings(s={}){
  const out=[];
  Object.entries(s.assessedRegions||{}).forEach(([region,a])=>(a?.findings||[]).forEach(f=>out.push({...f,region})));
  return out;
}
function sceneBaseRegion(region){return region==='left_foot'?'left_leg':region==='right_foot'?'right_leg':region;}
function sceneRegionAssessment(s,region){return s.assessedRegions?.[region]||s.assessedRegions?.[sceneBaseRegion(region)]||null;}
function sceneRegionCondition(s,region){
  const a=sceneRegionAssessment(s,region);
  if(!a) return 100;
  const sev=Math.max(0,...(a.findings||[]).map(f=>n(f.severity)));
  return Math.max(0,Math.round(100-sev));
}
function sceneTriageLabel(v){return ({CRITICAL:'Vermelha',HIGH:'Vermelha',MODERATE:'Amarela',LOW:'Verde',UNASSESSED:'Não definida'})[String(v||'UNASSESSED').toUpperCase()]||esc(v||'Não definida');}
function sceneVitalHr(s){const v=s?.vitals?.hr;return v==null?null:n(v);}
function scenePrimaryStatus(s){const done=['X','A','B','C','D','E'].filter(k=>s.xabcde?.[k]).length;return done===6?'Sincronizado':`${done}/6`;}
function sceneTreatmentCards(s,clinical){
  const loadout=clinical?.bagLoadout||{};
  const bag=state.medicalBag||state.bootstrap?.medicalBag||{};
  const ordered=['stethoscope','bp_cuff','pulse_oximeter','thermometer','pressure_bandage','wound_pack','tourniquet','chest_seal','c_collar','splint','opa','suction_kit','iv_kit','thermal_blanket','burn_dressing'];
  const keys=[...ordered.filter(k=>Object.prototype.hasOwnProperty.call(loadout,k)),...Object.keys(loadout).filter(k=>!ordered.includes(k))];
  const direct=`<div class="scene-treatment-item scene-treatment-skill" draggable="true" data-scene-treatment="direct_pressure"><span class="scene-item-icon">✚</span><span><b>Compressão direta</b><small>PROCEDIMENTO · SEM ITEM</small></span><em>∞</em></div>`;
  return direct+keys.map(key=>{
    const qty=n(bag[key]); const cat=sceneItemCategory(key); const treatment=clinicalSceneTreatmentByItem[key]; const measurement=clinicalSceneMeasurementByItem[key];
    const draggable=!!treatment&&qty>0; const clickable=!!measurement&&qty>0;
    return `<div class="scene-treatment-item ${qty<=0?'depleted':''} ${clickable?'measurement':''}" ${draggable?'draggable="true"':''} data-scene-item="${esc(key)}" ${treatment?`data-scene-treatment="${esc(treatment)}"`:''} ${measurement?`data-scene-measure="${esc(measurement)}"`:''}><span class="scene-item-icon">+</span><span><b>${esc(itemLabel(key))}</b><small>${esc(clinicalSceneCategoryLabels[cat]||cat.toUpperCase())}</small></span><em>x${qty}</em></div>`;
  }).join('');
}
function sceneMarkerMarkup(s,clinical){
  const regions=clinical?.regions||{};
  return Object.entries(regions).map(([key,r])=>{
    const assessed=!!sceneRegionAssessment(s,key);
    const sev=Math.max(0,...((sceneRegionAssessment(s,key)?.findings)||[]).map(f=>n(f.severity)));
    const cls=sev>0?injurySeverityClass(sev):'';
    return `<button class="scene-body-marker ${assessed?'assessed':''} ${cls}" data-scene-region="${key}" data-visible="0"><span class="scene-marker-plus">+</span><span class="scene-marker-label"><b>${esc(r.label||key)}</b><small>${sceneRegionCondition(s,key)}% saúde</small></span></button>`;
  }).join('');
}
function markerLabelSide(el,safeLeft,safeRight){
  const region=el.dataset.sceneRegion;
  const p=state.clinicalMarkerSmoothed?.[region]||state.clinicalMarkerPositions?.[region]||{};
  const x=n(p.x,.5)*window.innerWidth;
  const center=(safeLeft+safeRight)/2;
  const hysteresis=70;
  let side=state.clinicalLabelSides?.[region];

  if(!side) side=x>center?'left':'right';
  else if(side==='left' && x<center-hysteresis) side='right';
  else if(side==='right' && x>center+hysteresis) side='left';

  state.clinicalLabelSides[region]=side;
  return side;
}

function distributeMarkerLabelLane(items,minY,maxY,gap=39){
  if(!items.length)return;

  // Deterministic top-to-bottom packing. This avoids the old +/-18px retry
  // algorithm which changed lane on tiny bone/ragdoll movements and made labels
  // visibly jump in the video.
  items.sort((a,b)=>a.anchorY-b.anchorY);

  let cursor=minY;
  for(const item of items){
    item.targetY=Math.max(item.anchorY,cursor);
    cursor=item.targetY+gap;
  }

  // If we ran past the lower safe area, compact backwards while preserving order.
  let overflow=items[items.length-1].targetY-maxY;
  if(overflow>0){
    for(const item of items)item.targetY-=overflow;
    for(let i=items.length-2;i>=0;i--){
      const maxAllowed=items[i+1].targetY-gap;
      if(items[i].targetY>maxAllowed)items[i].targetY=maxAllowed;
    }
  }

  // Clamp first item and shift the whole lane down if necessary.
  const under=minY-items[0].targetY;
  if(under>0)for(const item of items)item.targetY+=under;

  for(const item of items){
    const dy=Math.round(item.targetY-item.anchorY);
    item.el.style.setProperty('--label-dy',`${dy}px`);
  }
}

function layoutClinicalMarkerLabels(){
  if(state.context!=='patient'||state.patientView!=='scene')return;
  const visible=[...document.querySelectorAll('.scene-body-marker[data-visible="1"]')];
  if(!visible.length)return;

  const leftPanel=document.querySelector('.scene-left-column')?.getBoundingClientRect();
  const rightPanel=document.querySelector('.scene-right-column')?.getBoundingClientRect();
  const safeLeft=(leftPanel?.right||0)+14;
  const safeRight=(rightPanel?.left||window.innerWidth)-14;
  const lanes={left:[],right:[]};

  for(const el of visible){
    const region=el.dataset.sceneRegion;
    const p=state.clinicalMarkerSmoothed?.[region]||state.clinicalMarkerPositions?.[region]||{};
    const anchorY=n(p.y,.5)*window.innerHeight;
    const side=markerLabelSide(el,safeLeft,safeRight);

    el.classList.toggle('label-left',side==='left');
    el.classList.toggle('label-right',side==='right');
    el.style.setProperty('--label-dy','0px');

    lanes[side].push({el,anchorY});
  }

  distributeMarkerLabelLane(lanes.left,92,window.innerHeight-40,39);
  distributeMarkerLabelLane(lanes.right,92,window.innerHeight-40,39);
}

function smoothClinicalMarker(region,p){
  if(!p||p.visible===false)return p;
  const current=state.clinicalMarkerSmoothed?.[region];
  if(!current||current.visible===false){
    const first={x:n(p.x,.5),y:n(p.y,.5),visible:true};
    state.clinicalMarkerSmoothed[region]=first;
    return first;
  }

  const tx=n(p.x,current.x), ty=n(p.y,current.y);
  const dx=tx-current.x, dy=ty-current.y;
  const dist=Math.hypot(dx,dy);

  // Small ragdoll/bone vibration is ignored; real camera/body movement follows
  // smoothly and quickly enough to keep the anatomical point accurate.
  if(dist<0.00055)return current;
  const alpha=dist>0.025?.55:dist>0.008?.32:.18;
  current.x+=dx*alpha;
  current.y+=dy*alpha;
  current.visible=true;
  return current;
}

function updateClinicalSceneMarkers(){
  if(state.context!=='patient'||state.patientView!=='scene')return;
  document.querySelectorAll('[data-scene-region]').forEach(el=>{
    const raw=state.clinicalMarkerPositions?.[el.dataset.sceneRegion];
    if(!raw||raw.visible===false){
      el.dataset.visible='0';
      if(state.clinicalMarkerSmoothed?.[el.dataset.sceneRegion])state.clinicalMarkerSmoothed[el.dataset.sceneRegion].visible=false;
      return;
    }
    const p=smoothClinicalMarker(el.dataset.sceneRegion,raw);
    el.dataset.visible='1';
    el.style.left=`${n(p.x)*100}%`;
    el.style.top=`${n(p.y)*100}%`;
  });

  requestAnimationFrame(layoutClinicalMarkerLabels);

  const pop=document.getElementById('sceneRegionPopover');
  if(pop&&state.clinicalRegion){
    const p=state.clinicalMarkerSmoothed?.[state.clinicalRegion]||state.clinicalMarkerPositions?.[state.clinicalRegion];
    if(p&&p.visible!==false){
      pop.style.left=`${Math.min(82,Math.max(18,n(p.x)*100+5))}%`;
      pop.style.top=`${Math.min(76,Math.max(20,n(p.y)*100-4))}%`;
    }
  }
}
function sceneRegionPopover(s,clinical){
  const region=state.clinicalRegion; if(!region)return '';
  const def=clinical?.regions?.[region]||{label:region}; const a=sceneRegionAssessment(s,region); const findings=a?.findings||[];
  const compatible=compatibleTreatments(region);
  return `<div id="sceneRegionPopover" class="scene-region-popover"><div class="scene-pop-head"><div><small>REGIÃO</small><b>${esc(def.label||region)}</b></div><button data-scene-pop-close>×</button></div>${!a?`<p>Região ainda não avaliada.</p><button class="scene-pop-primary" data-scene-assess="${region}">+ Avaliar região</button>`:`<div class="scene-pop-findings">${findings.length?findings.map(f=>`<div class="scene-pop-finding ${injurySeverityClass(f.severity)}"><b>${esc(f.title||'Achado')}</b><small>${Math.round(n(f.severity))}% · Dor ${Math.round(n(f.pain))}/100</small></div>`).join(''):'<div class="scene-pop-clear">Nenhum achado evidente.</div>'}</div><small class="scene-pop-caption">TRATAMENTOS COMPATÍVEIS</small><div class="scene-pop-actions">${compatible.map(([key,t])=>`<button data-scene-pop-treatment="${key}" data-scene-pop-region="${region}">${esc(t.label||key)}</button>`).join('')}</div>`}</div>`;
}
function pagePatientScene(){
  const s=state.targetState?.state||state.targetState||null;
  const clinical=state.clinicalCatalog||state.bootstrap?.clinicalCatalog||{};
  const ident=s?.identity||{};
  const findings=s?knownClinicalFindings(s):[];
  const hr=s?sceneVitalHr(s):null;
  const triage=s?.clinical?.triage||'UNASSESSED';
  const regionEntries=orderedClinicalRegions(clinical?.regions||{});
  sidebar.innerHTML='';
  if(!s){
    content.innerHTML=`<div class="scene-audit-loading"><img class="scene-loading-shield" src="assets/fiveems-shield.png" alt="FiveEMS"><img class="scene-loading-wordmark" src="assets/fiveems-wordmark.png" alt="FiveEMS"><h2>Carregando paciente...</h2><p>Aguardando o Medical Actor e o estado clínico.</p><button class="btn danger" id="sceneCloseLoading">Fechar</button></div>`;
    document.getElementById('sceneCloseLoading').onclick=close;
    if(!state.clinicalSceneActive){state.clinicalSceneActive=true;nui('clinicalSceneStart');}
    return;
  }
  content.innerHTML=`<div class="scene-audit-root">
    <div class="scene-brand"><img class="scene-brand-shield" src="assets/fiveems-shield.png" alt="FiveEMS"><div class="scene-brand-copy"><img class="scene-brand-wordmark" src="assets/fiveems-wordmark.png" alt="FiveEMS"><small>ATENDIMENTO AO PACIENTE</small></div></div>
    <div class="scene-topbar"><span class="scene-live-dot"></span><div class="scene-patient-id"><b>${esc(ident.nome_completo||ident.nome||'Paciente')}</b><small>${esc(s.mechanism||'Mecanismo Desconhecido')}</small></div><button data-scene-cam="prepare">Preparar paciente</button><button class="icon" title="Resetar câmera" data-scene-cam="reset">↻</button><button class="icon" title="Girar para esquerda" data-scene-cam="left">◀</button><button class="icon" title="Zoom -" data-scene-cam="zoom_out">－</button><button class="icon" title="Foco rápido" data-scene-cam="focus">◎</button><button class="icon" title="Zoom +" data-scene-cam="zoom_in">＋</button><button class="icon" title="Girar para direita" data-scene-cam="right">▶</button><button data-scene-record>Voltar ao prontuário</button><button class="danger" data-scene-close>Fechar</button></div>
    <aside class="scene-left-column">
      <section class="scene-panel scene-treatment-panel"><header><div class="scene-section-heading"><span class="scene-section-icon">✚</span><div><small>AUDITORIA CLÍNICA</small><h3>Itens de tratamento</h3></div></div></header><p class="scene-panel-help">Arraste um item até um marcador + ou clique no marcador para escolher o tratamento. Quando o paciente estiver no chão, o socorrista entra em postura ajoelhada automaticamente.</p><div class="scene-treatment-list">${sceneTreatmentCards(s,clinical)}</div></section>
      <section class="scene-panel scene-vital-panel"><header><div class="scene-section-heading"><span class="scene-section-icon pulse">⌁</span><small>SINAIS VITAIS</small></div><span class="scene-live-pill">AO VIVO</span></header><h3>Frequência cardíaca</h3><div class="scene-heart-row"><canvas id="sceneEcgCanvas"></canvas><strong>${hr==null?'--':Math.round(hr)} <span>bpm</span></strong></div><small>${hr==null?'Ainda não aferida. Use Pulso / FC.':`SpO₂ ${observedValue(s,'spo2')??'--'}% · PA ${observedValue(s,'sys')??'--'}/${observedValue(s,'dia')??'--'} · GCS ${observedValue(s,'gcs')??'--'}`}</small></section>
      <section class="scene-panel scene-region-status"><header><div class="scene-section-heading"><span class="scene-section-icon actor">●</span><div><small>STATUS DO ATOR</small><h3>Condição por região</h3></div></div></header><div>${regionEntries.map(([key,r])=>`<div class="scene-region-health" data-scene-health-region="${key}"><i class="scene-region-icon ${key}"></i><span><b>${esc(r.label||key)}</b><small>${sceneRegionAssessment(s,key)?'Avaliada':'Nenhum achado ativo.'}</small></span><em>${sceneRegionCondition(s,key)}%</em></div>`).join('')}</div></section>
    </aside>
    <div class="scene-body-overlay">${sceneMarkerMarkup(s,clinical)}${sceneRegionPopover(s,clinical)}</div>
    <aside class="scene-right-column">
      <section class="scene-panel scene-findings-panel"><header><div class="scene-section-heading"><span class="scene-section-icon list">▤</span><div><small>LISTA DE LESÕES</small><h3>Achados atuais</h3></div></div><span class="scene-count">${findings.length}</span></header><p class="scene-panel-help">As lesões descobertas aparecem ligadas aos indicadores do paciente real.</p><div class="scene-findings-list">${findings.length?findings.map(f=>`<div class="scene-finding-row ${injurySeverityClass(f.severity)}"><b>${esc(f.title||'Achado')}</b><small>${esc(clinical?.regions?.[f.region]?.label||f.region)} · ${Math.round(n(f.severity))}%</small></div>`).join(''):'<div class="scene-empty-box">Nenhuma lesão registrada.</div>'}</div></section>
      <section class="scene-panel scene-priority-panel"><header><div class="scene-section-heading"><span class="scene-section-icon priority">!</span><div><small>PRIORIDADE CLÍNICA</small><h3>Próxima conduta</h3></div></div></header><p>Paciente crítico. Controle ameaças imediatas e prepare transporte prioritário.</p><div class="scene-priority-row"><span>TRIAGEM</span><b class="${String(triage).toLowerCase()}">${sceneTriageLabel(triage)}</b></div><div class="scene-priority-row"><span>AVALIAÇÃO PRIMÁRIA</span><b>${scenePrimaryStatus(s)}</b></div><div class="scene-priority-row"><span>ACHADOS</span><b>${findings.length}</b></div><button class="scene-finish-button" data-scene-record>Finalizar avaliação</button></section>
    </aside>
  </div>`;

  if(!state.clinicalSceneActive){state.clinicalSceneActive=true;nui('clinicalSceneStart');}
  updateClinicalSceneMarkers();
  content.querySelectorAll('[data-scene-region]').forEach(b=>{
    b.onclick=()=>{state.clinicalRegion=b.dataset.sceneRegion;render();};
    b.ondragover=e=>{e.preventDefault();b.classList.add('dragover');};
    b.ondragleave=()=>b.classList.remove('dragover');
    b.ondrop=e=>{e.preventDefault();b.classList.remove('dragover');const treatment=e.dataTransfer.getData('fiveems/treatment');const measurement=e.dataTransfer.getData('fiveems/measurement');if(treatment)nui('applyTreatment',{injuryId:null,treatmentKey:treatment,region:b.dataset.sceneRegion});else if(measurement)nui('clinicalMeasureVital',{measurement});};
  });
  content.querySelectorAll('.scene-treatment-item').forEach(it=>{
    it.ondragstart=e=>{const t=it.dataset.sceneTreatment,m=it.dataset.sceneMeasure;if(t)e.dataTransfer.setData('fiveems/treatment',t);if(m)e.dataTransfer.setData('fiveems/measurement',m);e.dataTransfer.effectAllowed='copy';};
    if(it.dataset.sceneMeasure)it.onclick=()=>nui('clinicalMeasureVital',{measurement:it.dataset.sceneMeasure});
  });
  content.querySelectorAll('[data-scene-cam]').forEach(b=>b.onclick=()=>nui('clinicalSceneCamera',{action:b.dataset.sceneCam}));
  content.querySelectorAll('[data-scene-record]').forEach(b=>b.onclick=()=>{nui('clinicalSceneStop');state.clinicalSceneActive=false;state.patientView='record';state.patientTab='xabcde';render();});
  content.querySelector('[data-scene-close]').onclick=close;
  const pc=content.querySelector('[data-scene-pop-close]');if(pc)pc.onclick=()=>{state.clinicalRegion=null;render();};
  const pa=content.querySelector('[data-scene-assess]');if(pa)pa.onclick=()=>nui('clinicalAssessRegion',{region:pa.dataset.sceneAssess});
  content.querySelectorAll('[data-scene-pop-treatment]').forEach(b=>b.onclick=()=>nui('applyTreatment',{injuryId:null,treatmentKey:b.dataset.scenePopTreatment,region:b.dataset.scenePopRegion}));
  startSceneVitalsWave(s);
}

function observedVitalsBlock(s={}){
  const values={hr:observedValue(s,'hr'),rr:observedValue(s,'rr'),sys:observedValue(s,'sys'),dia:observedValue(s,'dia'),spo2:observedValue(s,'spo2'),temp:observedValue(s,'temp'),gcs:observedValue(s,'gcs')};
  const show=(v,suffix='')=>v===null||v===undefined?'--':`${typeof v==='number'&&suffix===' °C'?v.toFixed(1):v}${suffix}`;
  return `<div class="vitals clinical-observed-vitals"><div class="vital"><small>FC</small><strong>${show(values.hr)}</strong></div><div class="vital"><small>FR</small><strong>${show(values.rr)}</strong></div><div class="vital"><small>PA</small><strong style="font-size:22px">${values.sys==null?'--':values.sys}/${values.dia==null?'--':values.dia}</strong></div><div class="vital"><small>SpO₂</small><strong>${show(values.spo2,values.spo2==null?'':'%')}</strong></div><div class="vital"><small>Temp</small><strong>${show(values.temp,values.temp==null?'':' °C')}</strong></div><div class="vital"><small>GCS</small><strong>${show(values.gcs)}</strong></div></div>`;
}

function compatibleTreatments(region){
  const catalog=state.treatmentCatalog||state.bootstrap?.treatments||{};
  const clinical=state.clinicalCatalog||state.bootstrap?.clinicalCatalog||{};
  return Object.entries(catalog).filter(([key])=>{
    const regions=clinical?.treatmentRegions?.[key];
    return !Array.isArray(regions)||regions.includes(region);
  });
}

function bodyAuditMarkup(s, clinical){
  const regions=clinical?.regions||{
    head:{label:'Cabeça',x:50,y:8},neck:{label:'Pescoço',x:50,y:18},chest:{label:'Tórax',x:50,y:31},abdomen:{label:'Abdome',x:50,y:43},pelvis:{label:'Pelve',x:50,y:54},left_arm:{label:'Braço esquerdo',x:28,y:34},right_arm:{label:'Braço direito',x:72,y:34},left_leg:{label:'Perna esquerda',x:41,y:75},right_leg:{label:'Perna direita',x:59,y:75}
  };
  return `<div class="clinical-body-stage"><div class="clinical-human"><span class="human-head"></span><span class="human-neck"></span><span class="human-torso"></span><span class="human-pelvis"></span><span class="human-arm left"></span><span class="human-arm right"></span><span class="human-leg left"></span><span class="human-leg right"></span></div>${Object.entries(regions).map(([key,r])=>{
    const assessed=!!sceneRegionAssessment(s,key);
    const sev=Math.max(0,...(s.injuries||[]).filter(i=>sceneBaseRegion(i.region)===sceneBaseRegion(key)).map(i=>n(i.severity)));
    const cls=injurySeverityClass(sev);
    return `<button class="clinical-hotspot ${assessed?'assessed':''} ${sev>0?cls:''} ${state.clinicalRegion===key?'selected':''}" style="left:${n(r.x,50)}%;top:${n(r.y,50)}%" data-region="${key}" title="${esc(r.label||key)}"><b>+</b><span>${esc(r.label||key)}</span></button>`;
  }).join('')}</div>`;
}

function renderAuditPane(p,s,clinical){
  const region=state.clinicalRegion||'chest';
  const regionDef=clinical?.regions?.[region]||{label:region};
  const assessment=sceneRegionAssessment(s,region);
  const findings=assessment?.findings||[];
  const treatments=compatibleTreatments(region);
  const bag=state.medicalBag||state.bootstrap?.medicalBag||{};
  p.innerHTML=`<div class="clinical-audit-layout"><div class="card audit-body-card"><div class="row between"><div><div class="section-kicker">Scene Health Audit</div><h3>Selecione uma região pelo +</h3></div><span class="pill">${Object.keys(s.assessedRegions||{}).length} avaliada(s)</span></div>${bodyAuditMarkup(s,clinical)}<p class="label clinical-hint">Os + revelam achados apenas depois da avaliação. O estado clínico real continua server-authoritative.</p></div><div class="card clinical-region-panel"><div class="row between"><div><div class="section-kicker">Região selecionada</div><h2>${esc(regionDef.label||region)}</h2></div><span class="severity-chip ${injurySeverityClass(Math.max(0,...findings.map(f=>n(f.severity))))}">${assessment?'AVALIADA':'NÃO AVALIADA'}</span></div>${!assessment?`<div class="clinical-empty"><b>Nenhum achado revelado ainda.</b><p>Faça a avaliação física desta região para revelar somente os achados que o profissional conseguiria observar.</p><button class="btn primary" id="assessRegion">+ Avaliar ${esc(regionDef.label||region)}</button></div>`:`<div class="findings-list">${findings.length?findings.map(f=>`<div class="finding-card ${injurySeverityClass(f.severity)}"><div class="row between"><b>${esc(f.title||'Achado')}</b><span>${Math.round(n(f.severity))}%</span></div><small>Sangramento ${n(f.bleeding).toFixed(1)} · Dor ${Math.round(n(f.pain))}/100</small>${(f.treated||[]).length?`<div class="treated-tags">${f.treated.map(t=>`<span>${esc((state.treatmentCatalog||{})[t]?.label||t)}</span>`).join('')}</div>`:''}<div class="clinical-action-grid">${treatments.map(([key,t])=>{const need=t.item;const available=!need||clinical?.nonConsumableItems?.[need]?(!need||clinicalBagCount(need)>0):clinicalBagCount(need)>0;return `<button class="btn small ${available?'':'disabled'}" ${available?'':'disabled'} data-clinical-treat="${key}" data-region="${region}" data-injury="${esc(f.injuryId||'')}">${esc(t.label||key)}${need?` <em>${clinicalBagCount(need)}x</em>`:''}</button>`;}).join('')}</div></div>`).join(''):`<div class="clinical-clear"><b>Nenhuma lesão evidente nesta região.</b><p>A avaliação foi registrada na timeline.</p></div>`}<div class="clinical-general-actions"><h4>Procedimentos compatíveis</h4><div class="clinical-action-grid">${treatments.filter(([k,t])=>!findings.length||['c_collar','iv_access','thermal_blanket','airway_opa','suction'].includes(k)).map(([key,t])=>`<button class="btn small" data-clinical-treat="${key}" data-region="${region}">${esc(t.label||key)}${t.item?` · ${clinicalBagCount(t.item)}x`:''}</button>`).join('')}</div></div></div>`}</div></div>`;
  p.querySelectorAll('.clinical-hotspot[data-region]').forEach(b=>b.onclick=()=>{state.clinicalRegion=b.dataset.region;renderAuditPane(p,s,clinical);});
  const assess=document.getElementById('assessRegion');if(assess)assess.onclick=()=>nui('clinicalAssessRegion',{region});
  p.querySelectorAll('[data-clinical-treat]').forEach(b=>b.onclick=()=>nui('applyTreatment',{injuryId:b.dataset.injury||null,treatmentKey:b.dataset.clinicalTreat,region:b.dataset.region||region}));
}

function pagePatient(){
  nav([['os','⌂','Início'],['patient','✚','Paciente'],['monitor','♥','Monitor'],['reports','▤','Relatórios']],state.context);
  const s=state.targetState?.state||state.targetState||null;
  const clinical=state.clinicalCatalog||state.bootstrap?.clinicalCatalog||{};
  const ref=state.targetRef||state.extra?.targetRef||null;
  const target=state.targetServerId||state.extra?.targetServerId||'';
  let html=title('Atendimento ao Paciente','FiveFD Clinical Workflow adaptado ao FivePD SP: avaliação → estabilização → transporte → hospital → ePCR.',`<div class="row"><input id="targetId" style="width:90px" placeholder="ID" value="${esc(target)}"><button class="btn blue" id="loadPatient">Player ID</button></div>`);
  if(!s){html+=`<div class="card"><h3>Selecione um paciente</h3><p>Mire no Player/NPC com <b>ox_target → Atender paciente</b>. O campo acima é apenas fallback para Player por Server ID.</p></div>`;content.innerHTML=html;loadPatient.onclick=()=>{state.targetServerId=n(targetId.value);nui('openPatient',{targetServerId:state.targetServerId});};return;}

  const ident=s.identity||{};
  const triage=s.clinical?.triage||'UNASSESSED';
  const kind=s.patientKind||ref?.kind||'player';
  const tabs=[['scene','✚ Auditoria em cena'],['xabcde','XABCDE'],['vitals','Sinais vitais'],['bag','Bolsa médica'],['oxygen','Oxigênio'],['timeline','Timeline'],['report','ePCR']];
  html+=`<div class="clinical-patient-header"><div><div class="label">Identidade canônica · fivepd_sp_records</div><h2>${esc(ident.nome_completo||ident.nome||'Paciente')}</h2><small>${kind==='npc'?'NPC persistente':'Player'} · RG ${esc(ident.rg||'—')} · ${esc(ident.sexo||'—')} · ${esc(ident.idade??'—')} anos · Sangue ${esc(ident.tipo_sanguineo||'—')}</small></div><div class="clinical-header-badges"><span class="pill">${esc(triage)}</span><span class="pill">${(s.injuries||[]).length} lesão(ões)</span></div></div><div class="spacer"></div>${observedVitalsBlock(s)}<div class="clinical-privacy-note">Os valores acima aparecem somente depois de serem aferidos. O monitor multiparamétrico continua sendo um aparelho separado.</div><div class="spacer"></div><div class="tabs clinical-tabs">${tabs.map(([id,l])=>`<button class="tab ${state.patientTab===id?'active':''}" data-ptab="${id}">${l}</button>`).join('')}</div><div id="patientPane"></div>`;
  content.innerHTML=html;
  loadPatient.onclick=()=>{state.targetServerId=n(targetId.value);nui('openPatient',{targetServerId:state.targetServerId});};
  content.querySelectorAll('[data-ptab]').forEach(b=>b.onclick=()=>{if(b.dataset.ptab==='scene'){state.patientView='scene';state.clinicalRegion=null;render();return;}state.patientTab=b.dataset.ptab;pagePatient();});
  const p=document.getElementById('patientPane');


  if(state.patientTab==='xabcde'){
    const xabcde=clinical?.xabcde||{};
    p.innerHTML=`<div class="xabcde-grid">${Object.entries(xabcde).map(([key,d])=>{const done=s.xabcde?.[key];return `<div class="xabcde-card ${done?'done':''}"><div class="xabcde-letter">${key}</div><div><h3>${esc(d.label||key)}</h3><p>${done?`${esc(done.finding||'Avaliado')} · ${formatClinicalTime(done.at)}`:'Ainda não avaliado.'}</p><button class="btn ${done?'':'primary'} small" data-xabcde="${key}">${done?'Reavaliar':'Avaliar'}</button></div></div>`;}).join('')}</div>`;
    p.querySelectorAll('[data-xabcde]').forEach(b=>b.onclick=()=>nui('clinicalAssessXABCDE',{step:b.dataset.xabcde}));
  }

  if(state.patientTab==='vitals'){
    const measurements=clinical?.vitalMeasurements||{};
    const observed=s.observedVitals||{};
    p.innerHTML=`<div class="section-head"><div><div class="section-kicker">Aferição real</div><h2>Sinais vitais</h2><p>O Medical Engine conhece a fisiologia; o profissional só vê o que realmente aferiu.</p></div></div><div class="measurement-grid">${Object.entries(measurements).map(([key,d])=>{const o=observed[key];const values=(d.values||[]).map(k=>`${k.toUpperCase()}: ${o&&o[k]!=null?esc(o[k]):'--'}`).join(' · ');return `<div class="measurement-card ${o?'measured':''}"><div class="row between"><h3>${esc(d.label||key)}</h3>${d.equipment?`<span class="pill">${esc(itemLabel(d.equipment))} · ${clinicalBagCount(d.equipment)}x</span>`:'<span class="pill">Clínico</span>'}</div><div class="measurement-result">${o?(o.finding?esc(o.finding):values):'Não aferido'}</div><small>${o?`Última aferição ${formatClinicalTime(o.at)}`:'Realize a ação para revelar o valor.'}</small><button class="btn ${o?'':'primary'}" data-measure="${key}">${o?'Reaferir':'Aferir'}</button></div>`;}).join('')}</div>`;
    p.querySelectorAll('[data-measure]').forEach(b=>b.onclick=()=>nui('clinicalMeasureVital',{measurement:b.dataset.measure}));
  }

  if(state.patientTab==='bag'){
    const bag=state.medicalBag||state.bootstrap?.medicalBag||{};
    const loadout=clinical?.bagLoadout||{};
    p.innerHTML=`<div class="section-head"><div><div class="section-kicker">Medical Bag</div><h2>Bolsa médica</h2><p>Consumíveis são removidos no servidor quando um procedimento é aplicado.</p></div><button class="btn primary" id="restockBag">Reabastecer no ponto de suprimentos</button></div><div class="bag-grid">${Object.entries(loadout).map(([key,targetQty])=>{const qty=n(bag[key]);return `<div class="bag-item ${qty<=0?'empty':''}"><div><b>${esc(itemLabel(key))}</b><small>${clinical?.nonConsumableItems?.[key]?'Equipamento durável':'Consumível'}</small></div><strong>${qty}<span> / ${targetQty}</span></strong></div>`;}).join('')}</div>`;
    restockBag.onclick=()=>nui('clinicalRestockBag');
  }

  if(state.patientTab==='oxygen'){
    const v=s.vitals||{};
    p.innerHTML=`<div class="grid two"><div class="card"><div class="section-kicker">Suporte respiratório</div><h3>Oxigenoterapia regulável</h3>${selectField('Dispositivo','o2Device',[['nasal_cannula','Cânula nasal'],['simple_mask','Máscara simples'],['non_rebreather','Máscara não reinalante'],['bvm','BVM']],'nasal_cannula')}${field('Fluxo (L/min)','o2Flow',2,'number','min="1" max="15" step="1"')}<div class="row"><button class="btn primary" id="startO2">Iniciar/ajustar</button><button class="btn danger" id="stopO2">Parar</button></div></div><div class="card"><h3>Suporte atual</h3><div class="stat">${esc(s.oxygenDevice||'Sem O₂')}</div><p>Fluxo: ${n(s.oxygenFlow)} L/min</p><p>SpO₂ aferida: ${observedValue(s,'spo2')??'--'}${observedValue(s,'spo2')!=null?'%':''}</p><p class="label">O efeito é aplicado à mesma fisiologia usada pelo monitor e pelo prontuário.</p></div></div>`;
    startO2.onclick=()=>nui('setOxygen',{device:o2Device.value,flow:n(o2Flow.value)});stopO2.onclick=()=>nui('stopOxygen');
  }

  if(state.patientTab==='timeline'){
    const timeline=[...(s.timeline||[])].reverse();
    p.innerHTML=`<div class="section-head"><div><div class="section-kicker">Registro automático</div><h2>Patient Timeline</h2><p>Avaliações, aferições e tratamentos entram no ePCR sem digitação duplicada.</p></div></div><div class="timeline-list">${timeline.map(ev=>`<div class="timeline-event"><time>${formatClinicalTime(ev.at)}</time><span class="timeline-dot"></span><div><b>${esc(ev.label||ev.type)}</b><small>${esc(ev.type||'evento')}</small></div></div>`).join('')||'<div class="card"><p>Nenhum evento clínico registrado ainda.</p></div>'}</div>`;
  }

  if(state.patientTab==='report'){
    const assessed=Object.keys(s.assessedRegions||{}).length;
    const measured=Object.keys(s.observedVitals||{}).length;
    p.innerHTML=`<div class="epcr-summary"><div><span>Avaliações</span><b>${assessed}</b></div><div><span>Aferições</span><b>${measured}</b></div><div><span>Tratamentos</span><b>${Object.keys(s.treatments||{}).length}</b></div><div><span>Timeline</span><b>${(s.timeline||[]).length}</b></div></div><div class="grid two"><div class="card"><div class="section-kicker">ePCR</div><h3>Relatório pré-hospitalar</h3><p class="label">Lesões, aferições, XABCDE, tratamentos e timeline são anexados automaticamente.</p><div class="field"><label>Mecanismo da ocorrência</label><textarea id="repMechanism"></textarea></div><div class="field"><label>Sinais / sintomas relevantes</label><textarea id="repSigns"></textarea></div><div class="field"><label>Evolução / observações</label><textarea id="repTreatment"></textarea></div></div><div class="card"><h3>SAMPLA / Handoff</h3>${field('Alergias','repAllergies','')}${field('Medicações em uso','repMeds','')}${field('Antecedentes','repHistory','')}<div class="field"><label>Entrega / observações ao hospital</label><textarea id="repHandover"></textarea></div><button class="btn primary" id="sendReport">Enviar ePCR</button></div></div>`;
    sendReport.onclick=()=>nui('submitReport',{form:{mechanism:repMechanism.value,signs:repSigns.value,treatment:repTreatment.value,allergies:repAllergies.value,medications:repMeds.value,history:repHistory.value,handover:repHandover.value}});
  }
}


function formatBedDate(value){
  if(!value)return '—';
  const raw=String(value);
  const d=new Date(raw.includes('T')?raw:raw.replace(' ','T'));
  if(Number.isNaN(d.getTime()))return esc(raw);
  return d.toLocaleString('pt-BR',{day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'});
}
function bedText(value,fallback='Não informado'){
  const v=String(value??'').trim(); return v?esc(v):fallback;
}
function bedObservedSummary(s={}){
  const get=k=>observedValue(s,k);
  const hr=get('hr'),rr=get('rr'),sys=get('sys'),dia=get('dia'),spo2=get('spo2'),temp=get('temp'),gcs=get('gcs');
  const val=v=>v==null?'--':esc(v);
  return `<div class="bed-vitals-strip"><div><small>FC</small><b>${val(hr)}</b><span>bpm</span></div><div><small>FR</small><b>${val(rr)}</b><span>irpm</span></div><div><small>PA</small><b>${sys==null?'--':val(sys)}/${dia==null?'--':val(dia)}</b><span>mmHg</span></div><div><small>SpO₂</small><b>${val(spo2)}</b><span>%</span></div><div><small>Temp</small><b>${temp==null?'--':Number(temp).toFixed(1)}</b><span>°C</span></div><div><small>GCS</small><b>${val(gcs)}</b><span>/15</span></div></div>`;
}
function bedTimelineRows(s={},filter=null){
  let events=[...(s.timeline||[])].reverse();
  if(filter)events=events.filter(filter);
  if(!events.length)return '<div class="bed-empty">Nenhum registro disponível.</div>';
  return `<div class="bed-timeline">${events.map(ev=>`<div class="bed-timeline-row"><time>${formatClinicalTime(ev.at)}</time><span class="bed-timeline-dot"></span><div><b>${esc(ev.label||ev.type||'Registro')}</b><small>${esc(ev.type||'evento')}</small></div></div>`).join('')}</div>`;
}
function pageBedChart(){
  sidebar.innerHTML='';
  const payload=state.bedChart;
  if(!payload||!payload.state){
    content.innerHTML=`<div class="bed-chart-shell"><div class="bed-clipboard"><div class="bed-clip"></div><div class="bed-loading"><img src="assets/fiveems-shield.png" alt="FiveEMS"><h2>Carregando ficha do leito...</h2><p>Resolvendo o paciente que realmente ocupa este leito.</p><button class="btn danger" id="bedCloseLoading">Fechar</button></div></div></div>`;
    document.getElementById('bedCloseLoading').onclick=close;
    return;
  }
  const s=payload.state||{};
  const ident=s.identity||{};
  const chart=payload.chart||{};
  const bg=chart.background||{};
  const point=payload.carePoint||state.extra?.carePoint||{};
  const triage=sceneTriageLabel(s.clinical?.triage||'UNASSESSED');
  const tabs=[['summary','Resumo'],['evolution','Evolução'],['orders','Prescrição / Condutas'],['exams','Exames'],['nursing','Enfermagem'],['history','Histórico']];
  const kind=s.patientKind==='npc'?'NPC persistente':'Player';
  const injuries=s.injuries||[];
  const findings=knownClinicalFindings(s);
  const reports=chart.reports||[];
  const encounters=chart.encounters||[];
  const treatmentEntries=Object.entries(s.treatments||{}).sort((a,b)=>n(b[1]?.at)-n(a[1]?.at));

  content.innerHTML=`<div class="bed-chart-shell"><div class="bed-clipboard"><div class="bed-clip"></div>
    <header class="bed-chart-head"><div class="bed-hospital-brand"><img src="assets/fiveems-shield.png" alt="FiveEMS"><div><small>PRONTUÁRIO HOSPITALAR · FICHA DE LEITO</small><h1>${esc(ident.nome_completo||ident.nome||'Paciente')}</h1><p>${esc(point.label||'Leito')} · ${kind} · RG ${esc(ident.rg||'—')}</p></div></div><div class="bed-chart-actions"><span class="bed-status-pill">${esc(triage)}</span><button class="btn" id="bedRefresh">Atualizar ficha</button><button class="btn primary" id="bedOpenClinical">Abrir atendimento</button><button class="btn danger" id="bedClose">Fechar</button></div></header>
    <section class="bed-ident-strip"><div><small>Idade</small><b>${esc(ident.idade??'—')}</b></div><div><small>Sexo</small><b>${esc(ident.sexo||'—')}</b></div><div><small>Tipo sanguíneo</small><b>${esc(ident.tipo_sanguineo||'—')}</b></div><div><small>Leito</small><b>${esc(point.label||point.id||'—')}</b></div><div><small>Lesões conhecidas</small><b>${injuries.length}</b></div><div><small>Última atualização</small><b>${new Date().toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})}</b></div></section>
    ${bedObservedSummary(s)}
    <nav class="bed-tabs">${tabs.map(([id,label])=>`<button class="${state.bedChartTab===id?'active':''}" data-bed-tab="${id}">${label}</button>`).join('')}</nav>
    <main id="bedChartPane" class="bed-chart-pane"></main>
    <footer class="bed-chart-foot"><span>FiveEMS · Registro clínico do paciente no leito</span><span>As informações clínicas pertencem ao paciente identificado acima, não ao profissional que abriu a ficha.</span></footer>
  </div></div>`;

  const pane=document.getElementById('bedChartPane');
  if(state.bedChartTab==='summary'){
    pane.innerHTML=`<div class="bed-grid two"><section class="bed-paper-card"><h3>Identificação e admissão</h3><dl class="bed-data-list"><dt>Paciente</dt><dd>${esc(ident.nome_completo||ident.nome||'Paciente')}</dd><dt>Registro / RG</dt><dd>${esc(ident.rg||'—')}</dd><dt>Idade</dt><dd>${esc(ident.idade??'—')} anos</dd><dt>Sexo</dt><dd>${esc(ident.sexo||'—')}</dd><dt>Tipo sanguíneo</dt><dd>${esc(ident.tipo_sanguineo||'—')}</dd><dt>Classificação</dt><dd>${esc(triage)}</dd></dl></section>
      <section class="bed-paper-card warning"><h3>Alertas clínicos</h3><div class="bed-alert-row"><b>Alergias</b><span>${bedText(bg.allergies,'Não registradas no prontuário disponível')}</span></div><div class="bed-alert-row"><b>Medicamentos em uso</b><span>${bedText(bg.medications,'Não informados')}</span></div><div class="bed-alert-row"><b>Antecedentes</b><span>${bedText(bg.history,'Não informados')}</span></div></section></div>
      <div class="bed-grid two"><section class="bed-paper-card"><h3>Resumo clínico atual</h3><p><b>Hemorragia estimada:</b> ${Math.round(n(s.bleedingRate)*10)/10}</p><p><b>Dor:</b> ${Math.round(n(s.pain))}/100</p><p><b>Oxigenoterapia:</b> ${s.oxygenDevice?`${esc(s.oxygenDevice)} · ${n(s.oxygenFlow)} L/min`:'Sem suporte ativo'}</p><p><b>Acesso venoso:</b> ${s.ivAccess?'Presente':'Não registrado'}</p><p><b>Precaução cervical:</b> ${s.spinalPrecautions?'Ativa':'Não registrada'}</p></section><section class="bed-paper-card"><h3>Achados documentados</h3>${findings.length?findings.slice(0,8).map(f=>`<div class="bed-finding"><b>${esc(f.title||'Achado')}</b><span>${esc((state.clinicalCatalog||state.bootstrap?.clinicalCatalog||{}).regions?.[f.region]?.label||f.region)} · ${Math.round(n(f.severity))}%</span></div>`).join(''):'<div class="bed-empty">Nenhum achado documentado.</div>'}</section></div>`;
  }
  if(state.bedChartTab==='evolution'){
    pane.innerHTML=`<section class="bed-paper-card full"><div class="bed-section-title"><div><small>EVOLUÇÃO MULTIPROFISSIONAL</small><h3>Linha do tempo clínica</h3></div><span>${(s.timeline||[]).length} registro(s)</span></div>${bedTimelineRows(s)}</section>`;
  }
  if(state.bedChartTab==='orders'){
    pane.innerHTML=`<div class="bed-grid two"><section class="bed-paper-card"><h3>Condutas e suportes ativos</h3><div class="bed-order"><span>Oxigenoterapia</span><b>${s.oxygenDevice?`${esc(s.oxygenDevice)} · ${n(s.oxygenFlow)} L/min`:'Sem prescrição ativa'}</b></div><div class="bed-order"><span>Acesso venoso</span><b>${s.ivAccess?`Ativo · ${esc(s.ivAccess.region||'local não informado')}`:'Não registrado'}</b></div><div class="bed-order"><span>Precaução cervical</span><b>${s.spinalPrecautions?'Ativa':'Não registrada'}</b></div></section><section class="bed-paper-card"><h3>Procedimentos registrados</h3>${treatmentEntries.length?treatmentEntries.map(([key,t])=>`<div class="bed-order"><span>${esc((state.treatmentCatalog||state.bootstrap?.treatments||{})[key]?.label||key)}</span><b>${formatClinicalTime(t.at)} · ${esc(t.region||'')}</b></div>`).join(''):'<div class="bed-empty">Nenhum procedimento registrado.</div>'}</section></div><section class="bed-paper-card full"><h3>Prescrição medicamentosa</h3><div class="bed-prescription-placeholder"><b>Nenhuma prescrição medicamentosa hospitalar registrada neste atendimento.</b><span>Esta área fica pronta para a próxima etapa de medicações, dose, via, horário e checagem de administração.</span></div></section>`;
  }
  if(state.bedChartTab==='exams'){
    const observed=s.observedVitals||{};
    const assessed=s.assessedRegions||{};
    pane.innerHTML=`<div class="bed-grid two"><section class="bed-paper-card"><h3>Aferições / exames à beira-leito</h3>${Object.entries(observed).length?Object.entries(observed).map(([key,o])=>{const vals=Object.entries(o||{}).filter(([k])=>!['at','by','measurement','finding'].includes(k)).map(([k,v])=>`${k.toUpperCase()} ${v}`).join(' · ');return `<div class="bed-exam-row"><span>${esc((state.clinicalCatalog||state.bootstrap?.clinicalCatalog||{}).vitalMeasurements?.[key]?.label||key)}</span><b>${esc(o.finding||vals||'Registrado')}</b><small>${formatClinicalTime(o.at)}</small></div>`;}).join(''):'<div class="bed-empty">Nenhuma aferição registrada.</div>'}</section><section class="bed-paper-card"><h3>Exame físico documentado</h3>${Object.entries(assessed).length?Object.entries(assessed).map(([region,a])=>`<div class="bed-exam-row"><span>${esc((state.clinicalCatalog||state.bootstrap?.clinicalCatalog||{}).regions?.[region]?.label||region)}</span><b>${(a.findings||[]).length?`${a.findings.length} achado(s)`:'Sem achados'}</b><small>${formatClinicalTime(a.at)}</small></div>`).join(''):'<div class="bed-empty">Nenhuma região avaliada.</div>'}</section></div><section class="bed-paper-card full"><h3>Laboratório e imagem</h3><div class="bed-empty">Nenhum resultado laboratorial ou de imagem anexado a este prontuário ainda.</div></section>`;
  }
  if(state.bedChartTab==='nursing'){
    pane.innerHTML=`<div class="bed-grid two"><section class="bed-paper-card"><h3>Anotações / cuidados</h3>${bedTimelineRows(s,ev=>['treatment','vital','assessment'].includes(String(ev.type||'')))}</section><section class="bed-paper-card"><h3>Checagem do cuidado</h3><div class="bed-order"><span>Oxigênio</span><b>${s.oxygenDevice?'Em uso':'Não'}</b></div><div class="bed-order"><span>Acesso venoso</span><b>${s.ivAccess?'Sim':'Não'}</b></div><div class="bed-order"><span>Imobilização cervical</span><b>${s.spinalPrecautions?'Sim':'Não'}</b></div><div class="bed-order"><span>Tratamentos documentados</span><b>${treatmentEntries.length}</b></div></section></div>`;
  }
  if(state.bedChartTab==='history'){
    pane.innerHTML=`<div class="bed-grid two"><section class="bed-paper-card"><h3>Atendimentos / ePCR anteriores</h3>${reports.length?reports.map(r=>`<article class="bed-history-card"><header><b>${esc(r.type||'Relatório')}</b><time>${formatBedDate(r.created_at)}</time></header><p>${bedText(r.mechanism,'Mecanismo não informado')}</p>${r.handover?`<small>Handoff: ${esc(r.handover)}</small>`:''}</article>`).join(''):'<div class="bed-empty">Nenhum relatório anterior encontrado.</div>'}</section><section class="bed-paper-card"><h3>Passagens de atendimento</h3>${encounters.length?encounters.map(e=>`<div class="bed-encounter"><span>Atendimento #${esc(e.id)}</span><b>${esc(e.status||'')}</b><small>${formatBedDate(e.started_at)}${e.closed_at?` → ${formatBedDate(e.closed_at)}`:''}</small></div>`).join(''):'<div class="bed-empty">Nenhuma passagem anterior encontrada.</div>'}</section></div>`;
  }

  content.querySelectorAll('[data-bed-tab]').forEach(b=>b.onclick=()=>{state.bedChartTab=b.dataset.bedTab;pageBedChart();});
  document.getElementById('bedClose').onclick=close;
  document.getElementById('bedRefresh').onclick=()=>nui('bedChartRefresh',{pointId:point.id});
  document.getElementById('bedOpenClinical').onclick=()=>nui('bedChartOpenClinical');
}

function prepareWaveCanvas(canvas){
  if(!canvas)return null;
  const dpr=window.devicePixelRatio||1;
  const rect=canvas.getBoundingClientRect();
  if(rect.width<2||rect.height<2)return null;
  canvas.width=Math.max(2,Math.round(rect.width*dpr));
  canvas.height=Math.max(2,Math.round(rect.height*dpr));
  const ctx=canvas.getContext('2d');
  ctx.setTransform(dpr,0,0,dpr,0,0);
  ctx.clearRect(0,0,rect.width,rect.height);
  return {ctx,w:rect.width,h:rect.height};
}
function ecgSample(phase,rhythm='sinus'){
  phase=((phase%1)+1)%1;
  if(rhythm==='asystole')return Math.sin(phase*Math.PI*8)*.008;
  if(rhythm==='vf')return (Math.sin(phase*Math.PI*18)+Math.sin(phase*Math.PI*31)*.58+Math.sin(phase*Math.PI*47)*.33)*.28;
  if(rhythm==='pvt')return Math.sin(phase*Math.PI*9)*(.54+.24*Math.sin(phase*Math.PI*2));
  if(phase<.06)return Math.sin((phase/.06)*Math.PI)*.10;
  if(phase<.105)return -((phase-.06)/.045)*.13;
  if(phase<.145)return -.13+((phase-.105)/.04)*1.05;
  if(phase<.19)return .92-((phase-.145)/.045)*1.28;
  if(phase<.235)return -.36+((phase-.19)/.045)*.36;
  if(phase>.34&&phase<.58)return Math.sin(((phase-.34)/.24)*Math.PI)*.24;
  return 0;
}
function plethSample(phase){
  phase=((phase%1)+1)%1;
  if(phase<.13)return Math.sin((phase/.13)*Math.PI/2);
  if(phase<.35)return 1-((phase-.13)/.22)*.43;
  if(phase<.48)return .57+Math.sin(((phase-.35)/.13)*Math.PI)*.10;
  return Math.max(0,.57*(1-(phase-.48)/.52));
}
function respSample(phase){return Math.sin(phase*Math.PI*2);}
function capnoSample(phase){
  phase=((phase%1)+1)%1;
  if(phase<.12)return phase/.12;
  if(phase<.58)return .88+.08*Math.sin((phase-.12)*Math.PI*3);
  if(phase<.70)return 1-((phase-.58)/.12);
  return 0;
}
function drawPhysioWave(canvas,type,v={},opts={}){
  const prep=prepareWaveCanvas(canvas);if(!prep)return;
  const {ctx,w,h}=prep;
  const now=(opts.time??performance.now())/1000;
  const rawHr=Math.max(0,n(v.hr,0));
  const rawRr=Math.max(0,n(v.rr,0));
  const hr=Math.max(1,Math.min(240,rawHr));
  const rr=Math.max(1,Math.min(60,rawRr));
  const spo2=Math.max(0,n(v.spo2,0));
  const etco2=Math.max(0,n(v.etco2,0));
  const rhythm=String(v.rhythm||'sinus').toLowerCase();
  const color=opts.color||({ecg:'#61f26f',pleth:'#55d9ff',resp:'#e6dc4a',capno:'#f1f1f1'})[type]||'#61f26f';

  ctx.lineWidth=opts.lineWidth||1.8;
  ctx.strokeStyle=color;
  ctx.shadowBlur=opts.glow===false?0:5;
  ctx.shadowColor=color;
  ctx.beginPath();

  const seconds=type==='resp'||type==='capno'?10:7.2;
  for(let x=0;x<w;x++){
    const back=(w-x)/w*seconds;
    let y=0;

    if(type==='ecg'){
      // FiveEMS gameplay rule: 0 bpm = electrical baseline on the monitor.
      // As HR rises/falls, QRS density changes directly with the rate.
      if(rawHr>0){
        const phase=(now-back)*(hr/60);
        y=ecgSample(phase,rhythm);
      }
    }else if(type==='pleth'){
      // Pleth is pulse-derived. No pulse or no SpO2 signal => flat baseline.
      if(rawHr>0 && spo2>0 && rhythm!=='asystole'){
        const phase=(now-back)*(hr/60);
        const amp=Math.max(.30,Math.min(1,spo2/98));
        y=plethSample(phase)*amp;
      }
    }else if(type==='resp'){
      // Respiratory sweep follows respiratory rate; apnea is flat.
      if(rawRr>0){
        const phase=(now-back)*(rr/60);
        y=respSample(phase)*.70;
      }
    }else{
      // Capnography needs both respiratory cycles and an EtCO2 signal.
      if(rawRr>0 && etco2>0){
        const phase=(now-back)*(rr/60);
        const amp=Math.max(.25,Math.min(1.15,etco2/38));
        y=capnoSample(phase)*.85*amp;
      }
    }
    const yy=h*.55-y*h*.40;
    if(x===0)ctx.moveTo(x,yy);else ctx.lineTo(x,yy);
  }
  ctx.stroke();
  ctx.shadowBlur=0;
}
function drawWave(canvas,rhythm='sinus',rate=78){
  drawPhysioWave(canvas,'ecg',{rhythm,hr:rate});
}
let waveTimer=null,beepTimer=null,alarmTimer=null,sceneWaveTimer=null;
let alarmTimeouts=[];
let monitorAudioSignature=null;
let audioCtx=null;
function ensureAudio(){
  if(!audioCtx){
    const AC=window.AudioContext||window.webkitAudioContext;
    if(AC) audioCtx=new AC();
  }
  if(audioCtx?.state==='suspended') audioCtx.resume().catch(()=>{});
  return audioCtx;
}
function monitorTone(freq=880,duration=.045,gain=.035,type='sine'){
  const ac=ensureAudio(); if(!ac) return;
  const osc=ac.createOscillator(), vol=ac.createGain();
  osc.type=type; osc.frequency.setValueAtTime(freq,ac.currentTime);
  vol.gain.setValueAtTime(0.0001,ac.currentTime);
  vol.gain.exponentialRampToValueAtTime(Math.max(.0002,gain),ac.currentTime+.006);
  vol.gain.exponentialRampToValueAtTime(.0001,ac.currentTime+duration);
  osc.connect(vol); vol.connect(ac.destination); osc.start(); osc.stop(ac.currentTime+duration+.015);
}
function clearMonitorAudioTimers(){
  // v0.4.5a: this used to call itself recursively and caused
  // "Maximum call stack size exceeded" whenever ESC/Close/Disconnect
  // attempted to clean the monitor audio.
  clearInterval(beepTimer);beepTimer=null;
  clearInterval(alarmTimer);alarmTimer=null;
  for(const t of alarmTimeouts)clearTimeout(t);
  alarmTimeouts=[];
  monitorAudioSignature=null;
}
function monitorAlarmSequence(priority='high'){
  const cfg=state.bootstrap?.config?.monitor||{};
  if(cfg.beepEnabled===false||state.monitorUi?.muted||!monitorAudioActive())return;
  const gain=Math.max(.01,n(cfg.alarmVolume,.060));
  const schedule=(delay,freq,dur=.085)=>{
    alarmTimeouts.push(setTimeout(()=>monitorTone(freq,dur,gain,'square'),delay));
  };
  if(priority==='critical'){
    // Three short high-priority alarm pulses, separate from pulse/SpO2 tone.
    schedule(0,620,.09);schedule(145,620,.09);schedule(290,620,.11);
  }else{
    schedule(0,520,.08);schedule(190,520,.08);
  }
}
function restartMonitorBeep(v={}){
  const cfg=state.bootstrap?.config?.monitor||{};
  const sig=[Math.round(Math.max(0,n(v.hr,0))),String(v.rhythm||'sinus').toLowerCase(),Math.round(Math.max(0,n(v.spo2,0))),Math.round(Math.max(0,n(v.rr,0))),Math.round(Math.max(0,n(v.sys,0))),!!state.monitorUi?.muted].join('|');
  if(sig===monitorAudioSignature && (beepTimer||alarmTimer))return;
  clearMonitorAudioTimers();
  monitorAudioSignature=sig;
  if(cfg.beepEnabled===false || state.monitorUi?.muted || !monitorAudioActive()) return;

  const hr=Math.max(0,n(v.hr,0));
  const rr=Math.max(0,n(v.rr,0));
  const rhythm=String(v.rhythm||'sinus').toLowerCase();
  const spo2=Math.max(0,n(v.spo2,0));
  const sys=Math.max(0,n(v.sys,0));
  const alarms=cfg.alarms||{};
  const pulseAvailable=hr>0 && rhythm!=='asystole';

  // Pulse tone: cadence follows the real HR. No heart rate = no pulse beep.
  if(pulseAvailable){
    const satForPitch=Math.max(70,Math.min(100,spo2||95));
    const normalPitch=Math.max(520,Math.min(1040,620+(satForPitch-80)*18));
    const pulseGain=Math.max(.008,n(cfg.pulseVolume,.035));
    const pulse=()=>monitorTone(normalPitch,.045,pulseGain,'sine');
    pulse();
    beepTimer=setInterval(pulse,Math.max(250,60000/Math.max(20,Math.min(240,hr))));
  }

  const criticalNoPulse=hr<=0 || rhythm==='asystole';
  const criticalResp=rr<=0;
  const highAlarm=criticalNoPulse||criticalResp||
    (alarms.spo2Low&&spo2>0&&spo2<alarms.spo2Low)||
    (alarms.sysLow&&sys>0&&sys<alarms.sysLow)||
    (alarms.hrLow&&hr>0&&hr<alarms.hrLow)||
    (alarms.hrHigh&&hr>alarms.hrHigh);

  if(highAlarm){
    const priority=(criticalNoPulse||criticalResp)?'critical':'high';
    const repeat=Math.max(900,n(cfg.alarmRepeatMs,1800));
    const alarm=()=>monitorAlarmSequence(priority);
    alarm();
    alarmTimer=setInterval(alarm,repeat);
  }
}
function startSceneVitalsWave(s={}){
  clearInterval(sceneWaveTimer);
  const v=s.vitals||{};
  const render=()=>drawPhysioWave(document.getElementById('sceneEcgCanvas'),'ecg',v,{color:'#55e0bd',lineWidth:1.65});
  render();
  sceneWaveTimer=setInterval(render,45);
}
function startMonitorWaves(v={}){
  clearInterval(waveTimer);clearInterval(sceneWaveTimer);
  const draw=()=>{
    if(state.monitorUi?.frozen)return;
    drawPhysioWave(document.getElementById('monEcg'),'ecg',v,{color:'#67f26d'});
    drawPhysioWave(document.getElementById('monPleth'),'pleth',v,{color:'#4bd8ff'});
    drawPhysioWave(document.getElementById('monResp'),'resp',v,{color:'#e7df4c'});
    drawPhysioWave(document.getElementById('monCapno'),'capno',v,{color:'#e9edf0'});
  };
  draw();
  if(!state.monitorUi?.frozen)waveTimer=setInterval(draw,45);
}
window.addEventListener('pointerdown',()=>ensureAudio(),{passive:true});
function monitorAlarmState(v={}){
  const cfg=state.bootstrap?.config?.monitor?.alarms||{};
  const hr=Math.max(0,n(v.hr,0)),rr=Math.max(0,n(v.rr,0)),spo2=Math.max(0,n(v.spo2,0)),sys=Math.max(0,n(v.sys,0)),temp=n(v.temp,36.8);
  const rhythm=String(v.rhythm||'sinus').toLowerCase();
  const flags=[];
  if(hr<=0||rhythm==='asystole')flags.push('SEM PULSO');
  else if(cfg.hrLow&&hr<cfg.hrLow)flags.push('FC BAIXA');
  else if(cfg.hrHigh&&hr>cfg.hrHigh)flags.push('FC ALTA');
  if(rr<=0)flags.push('APNEIA');
  if(cfg.spo2Low&&spo2>0&&spo2<cfg.spo2Low)flags.push('SpO₂ BAIXA');
  if(cfg.sysLow&&sys>0&&sys<cfg.sysLow)flags.push('PA BAIXA');
  if(cfg.tempLow&&temp<cfg.tempLow)flags.push('TEMP BAIXA');
  if(cfg.tempHigh&&temp>cfg.tempHigh)flags.push('TEMP ALTA');
  return flags;
}
function monitorPatientLabel(s={}){
  return s?.identity?.nome_completo||s?.identity?.nome||(
    state.targetRef?.kind==='npc' ? `Paciente NPC #${state.targetRef.netId}` :
    state.targetRef?.kind==='player' ? `Paciente #${state.targetRef.serverId}` : 'Paciente'
  );
}
function monitorMetric(label,value,unit,cls,small=''){
  return `<div class="mp-num ${cls||''}"><div class="mp-num-label">${label}${small?`<small>${small}</small>`:''}</div><strong>${value}</strong>${unit?`<span>${unit}</span>`:''}</div>`;
}

let monitorOverlayWaveTimer=null;
let monitorOverlayDrag=null;

function monitorOverlayVitals(){
  const s=state.monitorTargetState?.state||state.monitorTargetState||{};
  return {state:s,v:s.vitals||{}};
}

function applyMonitorOverlayGeometry(){
  if(!monitorOverlayEl)return;
  const o=state.monitorOverlay||{};
  const baseW=o.compact?520:690;
  const baseH=o.compact?230:360;
  const scale=Math.max(.38,Math.min(1.10,n(o.scale,.62)));
  const maxX=Math.max(8,window.innerWidth-baseW*scale-8);
  const maxY=Math.max(8,window.innerHeight-baseH*scale-8);
  const left=Math.max(8,Math.min(maxX,n(o.x,.62)*window.innerWidth));
  const top=Math.max(8,Math.min(maxY,n(o.y,.58)*window.innerHeight));
  monitorOverlayEl.style.left=`${left}px`;
  monitorOverlayEl.style.top=`${top}px`;
  monitorOverlayEl.style.transform=`scale(${scale})`;
  monitorOverlayEl.style.transformOrigin='top left';
}

function startMonitorOverlayWave(v={}){
  clearInterval(monitorOverlayWaveTimer);
  const draw=()=>{
    if(!monitorOverlayActive())return;
    drawPhysioWave(document.getElementById('overlayEcg'),'ecg',v,{color:'#67f26d',lineWidth:1.6});
    drawPhysioWave(document.getElementById('overlayPleth'),'pleth',v,{color:'#4bd8ff',lineWidth:1.4});
  };
  draw();
  monitorOverlayWaveTimer=setInterval(draw,45);
}

function bindMonitorOverlayDrag(){
  const handle=monitorOverlayEl?.querySelector('[data-monitor-overlay-drag]');
  if(!handle)return;
  handle.onpointerdown=e=>{
    if(state.monitorOverlay?.locked)return;
    const r=monitorOverlayEl.getBoundingClientRect();
    monitorOverlayDrag={dx:e.clientX-r.left,dy:e.clientY-r.top};
    handle.setPointerCapture?.(e.pointerId);
    e.preventDefault();
  };
}

document.addEventListener('pointermove',e=>{
  if(!monitorOverlayDrag||!state.monitorOverlay?.enabled)return;
  const scale=Math.max(.38,Math.min(1.10,n(state.monitorOverlay.scale,.62)));
  const baseW=(state.monitorOverlay.compact?520:690)*scale;
  const baseH=(state.monitorOverlay.compact?230:360)*scale;
  const left=Math.max(8,Math.min(window.innerWidth-baseW-8,e.clientX-monitorOverlayDrag.dx));
  const top=Math.max(8,Math.min(window.innerHeight-baseH-8,e.clientY-monitorOverlayDrag.dy));
  state.monitorOverlay.x=left/window.innerWidth;
  state.monitorOverlay.y=top/window.innerHeight;
  applyMonitorOverlayGeometry();
});
document.addEventListener('pointerup',()=>{if(monitorOverlayDrag){monitorOverlayDrag=null;saveMonitorOverlayPrefs();}});
window.addEventListener('resize',applyMonitorOverlayGeometry);

function renderMonitorOverlay(){
  if(!monitorOverlayEl)return;
  if(!monitorOverlayActive()){
    monitorOverlayEl.classList.add('hidden');
    clearInterval(monitorOverlayWaveTimer);monitorOverlayWaveTimer=null;
    return;
  }

  const {state:s,v}=monitorOverlayVitals();
  const hr=Math.round(Math.max(0,n(v.hr,0)));
  const rr=Math.round(Math.max(0,n(v.rr,0)));
  const spo2=Math.round(Math.max(0,n(v.spo2,0)));
  const sys=Math.round(Math.max(0,n(v.sys,0)));
  const dia=Math.round(Math.max(0,n(v.dia,0)));
  const rhythm=String(v.rhythm||'sinus').toUpperCase();
  const pulse=hr>0&&rhythm!=='ASYSTOLE';
  const alarms=monitorAlarmState(v);
  const patient=monitorPatientLabel(s);
  const o=state.monitorOverlay;

  monitorOverlayEl.className=`monitor-overlay ${o.compact?'compact':'expanded'} ${o.locked?'locked':''}`;
  monitorOverlayEl.innerHTML=`
    <section class="monitor-overlay-device">
      <header class="monitor-overlay-head" data-monitor-overlay-drag>
        <div><b>LIFEPAK 15 · FiveEMS</b><small>${esc(patient)} · ${rhythm}</small></div>
        <div class="monitor-overlay-controls">
          <button data-overlay-scale="down" title="Diminuir escala">−</button>
          <button data-overlay-scale="up" title="Aumentar escala">+</button>
          <button data-overlay-compact title="${o.compact?'Expandir':'Compactar'}">${o.compact?'▣':'▤'}</button>
          <button data-overlay-lock title="${o.locked?'Desbloquear posição':'Fixar posição'}">${o.locked?'🔒':'🔓'}</button>
        </div>
      </header>
      <div class="monitor-overlay-alarm ${alarms.length?'alarm':''}">${alarms.length?esc(alarms.join(' · ')):'MONITORANDO'}</div>
      <div class="monitor-overlay-body">
        <div class="monitor-overlay-waves">
          <div><span>ECG II</span><canvas id="overlayEcg"></canvas></div>
          <div><span>PLETH</span><canvas id="overlayPleth"></canvas></div>
        </div>
        <div class="monitor-overlay-numbers">
          <div class="green"><small>FC</small><b>${hr}</b><span>bpm</span></div>
          <div class="cyan"><small>SpO₂</small><b>${pulse&&spo2>0?spo2:'--'}</b><span>${pulse&&spo2>0?'%':''}</span></div>
          <div class="yellow"><small>FR</small><b>${rr}</b><span>irpm</span></div>
          <div class="white"><small>PNI</small><b>${sys}/${dia}</b><span>mmHg</span></div>
        </div>
      </div>
      <footer class="monitor-overlay-footer">
        <span>${state.monitorPortableNetId?`APARELHO #${esc(state.monitorPortableNetId)}`:'MONITOR'}</span>
        <div><button data-overlay-full>Monitor completo</button><button data-overlay-game>Continuar jogando</button><button class="danger" data-overlay-disconnect>Desconectar</button></div>
      </footer>
    </section>`;

  applyMonitorOverlayGeometry();
  bindMonitorOverlayDrag();
  startMonitorOverlayWave(v);

  monitorOverlayEl.querySelector('[data-overlay-scale="down"]')?.addEventListener('click',()=>{o.scale=Math.max(.38,n(o.scale,.62)-.08);saveMonitorOverlayPrefs();applyMonitorOverlayGeometry();});
  monitorOverlayEl.querySelector('[data-overlay-scale="up"]')?.addEventListener('click',()=>{o.scale=Math.min(1.10,n(o.scale,.62)+.08);saveMonitorOverlayPrefs();applyMonitorOverlayGeometry();});
  monitorOverlayEl.querySelector('[data-overlay-compact]')?.addEventListener('click',()=>{o.compact=!o.compact;saveMonitorOverlayPrefs();renderMonitorOverlay();});
  monitorOverlayEl.querySelector('[data-overlay-lock]')?.addEventListener('click',()=>{o.locked=!o.locked;saveMonitorOverlayPrefs();renderMonitorOverlay();});
  monitorOverlayEl.querySelector('[data-overlay-full]')?.addEventListener('click',()=>{state.context='monitor';state.open=true;frame.style.display='';root.style.pointerEvents='';render();});
  monitorOverlayEl.querySelector('[data-overlay-game]')?.addEventListener('click',()=>{nui('monitorOverlayRelease');state.context='overlay';state.open=true;frame.style.display='none';root.style.pointerEvents='none';renderMonitorOverlay();});
  monitorOverlayEl.querySelector('[data-overlay-disconnect]')?.addEventListener('click',async()=>{o.enabled=false;await nui('monitorDetach');close(true);});
}
function minimizeMonitorToOverlay(){
  if(!state.targetState)return toast('Conecte um paciente antes de usar o overlay.');
  state.monitorOverlay.enabled=true;
  state.monitorTargetState=state.targetState;
  state.monitorTargetRef=state.targetRef;
  state.monitorPortableNetId=state.extra?.portableMonitorNetId||state.monitorPortableNetId||null;
  saveMonitorOverlayPrefs();
  renderMonitorOverlay();
  state.context='overlay';
  state.open=true;
  frame.style.display='none';
  root.classList.remove('hidden');
  root.style.pointerEvents='';
  renderMonitorOverlay();
  restartMonitorBeep((state.monitorTargetState?.state||state.monitorTargetState||{}).vitals||{});
}

function pageMonitor(){
  nav([['os','⌂','Launcher'],['monitor','♥','Monitor'],['patient','✚','Paciente']],state.context);
  const hasTarget=!!(state.targetRef && state.targetState) || !!(state.targetServerId && state.targetState);
  const s=state.targetState?.state||state.targetState||{};
  const v=s.vitals||{};
  if(hasTarget){
    state.monitorTargetState=state.targetState;
    state.monitorTargetRef=state.targetRef;
    state.monitorPortableNetId=state.extra?.portableMonitorNetId||state.monitorPortableNetId||null;
  }

  if(!hasTarget){
    clearInterval(waveTimer);clearMonitorAudioTimers();
    content.innerHTML=title('Monitor Multiparamétrico','Aparelho hospitalar separado do computador, tablet e desfibrilador.',`<span class="pill">STANDBY</span>`)+`
      <section class="mp-device">
        <div class="mp-brandbar"><b>FiveEMS</b><span>Patient Monitor</span><div class="mp-status"><i></i> STANDBY · 🔋</div></div>
        <div class="mp-screen mp-standby">
          <div class="mp-standby-mark">♥</div>
          <h2>Monitor aguardando paciente</h2>
          <p>Conecte o aparelho ao NPC ou Player próximo. Os valores são lidos da mesma fisiologia usada no atendimento clínico.</p>
          <div class="mp-connect-row">
            <button class="mp-soft primary" id="attachNearest">Conectar paciente próximo</button>
            <div class="mp-id-connect">${field('Server ID (Player)','monitorTargetId','','number')}<button class="mp-soft" id="attachById">Conectar por ID</button></div>
          </div>
        </div>
        <div class="mp-hardware"><button class="mp-power" id="powerMon" title="Desligar monitor">⏻</button><span></span><span></span><button>☀</button><button>☎</button><button>▣</button><div class="mp-knob"></div></div>
      </section>`;
    attachNearest.onclick=()=>nui('monitorAttachNearest');
    attachById.onclick=()=>nui('monitorAttachById',{targetServerId:n(monitorTargetId.value)});
    return;
  }

  const hr=Math.round(Math.max(0,n(v.hr,0)));
  const rr=Math.round(Math.max(0,n(v.rr,0)));
  const rawSpo2=Math.round(Math.max(0,n(v.spo2,0)));
  const pulseSignal=hr>0 && String(v.rhythm||'sinus').toLowerCase()!=='asystole';
  const spo2Display=pulseSignal&&rawSpo2>0?rawSpo2:'--';
  const sys=Math.round(Math.max(0,n(v.sys,0))),dia=Math.round(Math.max(0,n(v.dia,0)));
  const map=(sys>0&&dia>0)?Math.round((sys+(2*dia))/3):0;
  const temp=Number(n(v.temp,0));
  const temp2=Math.max(0,temp-.1);
  const rawEtco2=Math.round(Math.max(0,n(v.etco2,0)));
  const etco2Display=rr>0?rawEtco2:0;
  const alarms=monitorAlarmState(v);
  const patient=monitorPatientLabel(s);
  const rhythm=String(v.rhythm||'sinus').toUpperCase();
  const nibpTime=state.monitorUi?.nibpAt?new Date(state.monitorUi.nibpAt).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'}):'AUTO';
  const clock=new Date().toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'});
  const alarmText=alarms.length?alarms.join(' · '):'SEM ALARMES';
  const alarmClass=alarms.length?'alarm':'normal';

  content.innerHTML=`
    <section class="mp-device">
      <div class="mp-brandbar">
        <div><b>FiveEMS</b><span>Multiparameter Patient Monitor</span></div>
        <div class="mp-patient-chip"><strong>${esc(patient)}</strong><small>${esc(s.identity?.sexo||'')} ${s.identity?.idade?`· ${esc(s.identity.idade)} anos`:''}</small></div>
        <div class="mp-status"><i class="${alarmClass}"></i>${clock} · Wi‑Fi · 🔋</div>
      </div>
      <div class="mp-screen">
        <div class="mp-alarmbar ${alarmClass}"><span>${alarmText}</span><small>${rhythm} · ${state.monitorUi?.frozen?'CONGELADO':'MONITORANDO'}</small></div>

        <div class="mp-main-grid">
          <div class="mp-waves">
            <div class="mp-channel ecg"><div class="mp-channel-tag"><b>ECG II</b><small>x1 · 25 mm/s</small></div><canvas id="monEcg"></canvas><div class="mp-side-num">${monitorMetric('FC',hr,'bpm','green')}</div></div>
            <div class="mp-channel pleth"><div class="mp-channel-tag"><b>PLETH</b><small>SpO₂</small></div><canvas id="monPleth"></canvas><div class="mp-side-num">${monitorMetric('SpO₂',spo2Display,spo2Display==='--'?'':'%','cyan')}</div></div>
            <div class="mp-channel resp"><div class="mp-channel-tag"><b>RESP</b><small>impedância</small></div><canvas id="monResp"></canvas><div class="mp-side-num">${monitorMetric('FR',rr,'irpm','yellow')}</div></div>
            <div class="mp-channel capno"><div class="mp-channel-tag"><b>CO₂</b><small>capnografia</small></div><canvas id="monCapno"></canvas><div class="mp-side-num">${monitorMetric('EtCO₂',etco2Display,'mmHg','white')}</div></div>
          </div>

          <aside class="mp-numerics">
            <div class="mp-nibp">
              <header><b>PNI / NIBP</b><span>${nibpTime}</span></header>
              <div class="mp-bp"><strong>${sys}<span>/</span>${dia}</strong><small>(${map}) mmHg</small></div>
            </div>
            <div class="mp-temp-grid">
              ${monitorMetric('TEMP 1',temp.toFixed(1),'°C','temp')}
              ${monitorMetric('TEMP 2',temp2.toFixed(1),'°C','temp')}
            </div>
            <div class="mp-mini-status">
              <div><span>RITMO</span><b>${rhythm}</b></div>
              <div><span>GCS</span><b>${Math.round(n(v.gcs,15))}</b></div>
              <div><span>O₂</span><b>${s.oxygenFlow?`${n(s.oxygenFlow)} L/min`:'AR AMBIENTE'}</b></div>
              <div><span>PULSO</span><b class="${pulseSignal?'ok':'danger'}">${pulseSignal?'DETECTADO':'AUSENTE'}</b></div>
            </div>
          </aside>
        </div>

        <div class="mp-softkeys">
          <button class="mp-soft" id="refreshMon">Atualizar</button>
          <button class="mp-soft" id="nibpMon">PNI</button>
          <button class="mp-soft" id="eventMon">Evento</button>
          <button class="mp-soft ${state.monitorUi?.frozen?'active':''}" id="freezeMon">${state.monitorUi?.frozen?'Retomar':'Congelar'}</button>
          <button class="mp-soft" id="reviewMon">Revisão</button>
          <button class="mp-soft ${state.monitorUi?.muted?'active':''}" id="muteMon">${state.monitorUi?.muted?'Som ligado':'Silêncio'}</button>
          <button class="mp-soft" id="menuMon">Menu</button>
          <button class="mp-soft primary" id="overlayMon">Overlay</button>
          <button class="mp-soft danger" id="detachMon">Desconectar</button>
        </div>
        ${state.monitorUi?.menu?`<div class="mp-menu-pop"><b>Configuração rápida</b><span>ECG: II</span><span>Velocidade: 25 mm/s</span><span>PNI: manual/auto</span><span>Alarmes: ${alarms.length?'ativos':'normais'}</span><small>O desfibrilador é um aparelho separado do FiveEMS.</small></div>`:''}
      </div>
      <div class="mp-hardware"><button class="mp-power" id="powerMonConnected" title="Fechar monitor">⏻</button><span></span><span></span><button>☀</button><button>☎</button><button>▣</button><div class="mp-knob"></div></div>
    </section>`;

  refreshMon.onclick=()=>nui('monitorRefresh');
  if(typeof powerMonConnected!=='undefined' && powerMonConnected) powerMonConnected.onclick=()=>close();
  overlayMon.onclick=()=>minimizeMonitorToOverlay();
  detachMon.onclick=async()=>{
    state.monitorOverlay.enabled=false;
    state.monitorTargetState=null;
    state.monitorTargetRef=null;
    await nui('monitorDetach');
    close(true);
  };
  nibpMon.onclick=()=>{state.monitorUi.nibpAt=Date.now();monitorTone(720,.055,.028);setTimeout(()=>monitorTone(820,.055,.028),110);nui('monitorRefresh');render();};
  eventMon.onclick=()=>{toast('Evento clínico marcado no monitor.');};
  freezeMon.onclick=()=>{state.monitorUi.frozen=!state.monitorUi.frozen;render();};
  reviewMon.onclick=()=>{toast('Revisão de tendências será alimentada pela Timeline/ePCR.');};
  muteMon.onclick=()=>{state.monitorUi.muted=!state.monitorUi.muted;if(state.monitorUi.muted)clearMonitorAudioTimers();render();};
  menuMon.onclick=()=>{state.monitorUi.menu=!state.monitorUi.menu;render();};

  startMonitorWaves(v);
  restartMonitorBeep(v);
}

function pageFieldBag(){
  sidebar.innerHTML='';
  const d=state.extra||{}; const items=d.items||[];
  content.innerHTML=title('Bolsa médica de cena','Retire o material para suas mãos e depois use Tratamentos EMS no ox_target do paciente. Consumíveis só são gastos quando o procedimento termina.')+`<div class="field-equip-toolbar"><span class="pill">Bolsa #${n(d.netId)}</span><button class="btn" id="fieldBagRefresh">Atualizar</button></div><div class="field-bag-grid">${items.map(i=>`<div class="field-bag-row"><div><b>${esc(i.label||i.name)}</b><small>${i.durable?'Equipamento durável':'Consumível'} · Alvo ${n(i.target)}</small></div><div class="field-bag-counts"><span>Bolsa <strong>${n(i.bag)}</strong></span><span>Em mãos <strong>${n(i.hand)}</strong></span></div><div class="row"><button class="btn small" data-field-take="${esc(i.name)}" ${n(i.bag)<=0?'disabled':''}>Pegar para usar</button><button class="btn small" data-field-return="${esc(i.name)}" ${n(i.hand)<=0?'disabled':''}>Devolver à bolsa</button></div></div>`).join('')||'<div class="card">Bolsa vazia.</div>'}</div>`;
  fieldBagRefresh.onclick=()=>nui('fieldBagRefresh',{netId:n(d.netId)});
  content.querySelectorAll('[data-field-take]').forEach(b=>b.onclick=()=>nui('fieldBagTake',{netId:n(d.netId),item:b.dataset.fieldTake,count:1}));
  content.querySelectorAll('[data-field-return]').forEach(b=>b.onclick=()=>nui('fieldBagReturn',{netId:n(d.netId),item:b.dataset.fieldReturn,count:1}));
}

function pageVehicleEquipment(){
  sidebar.innerHTML='';
  const d=state.extra||{}; const supplies=d.supplies||[]; const loadout=d.bagLoadout||{}; const bag=d.bag||{};
  content.innerHTML=title('Compartimento EMS da viatura','Acesse equipamentos, LIFEPAK, bolsa médica e reabasteça a bolsa diretamente pela ambulância.')+`<div class="field-equip-toolbar"><span class="pill">Viatura conectada</span><button class="btn primary" id="restockVehicleBag">Reabastecer bolsa</button><button class="btn" id="vehicleEquipRefresh">Atualizar</button></div><div class="table-wrap field-vehicle-table"><table><thead><tr><th>Item</th><th>Categoria</th><th>Estoque</th><th>Bolsa</th><th>Ações</th></tr></thead><tbody>${supplies.map(i=>`<tr><td><b>${esc(i.label)}</b><br><small>${esc(i.item_name)}</small></td><td>${esc(i.category)}</td><td>${n(i.quantity)}</td><td>${Object.prototype.hasOwnProperty.call(loadout,i.item_name)?`${n(bag[i.item_name])}/${n(loadout[i.item_name])}`:'—'}</td><td><div class="row"><button class="btn small" data-veh-take="${i.id}" ${n(i.quantity)<=0?'disabled':''}>Pegar 1</button>${Object.prototype.hasOwnProperty.call(loadout,i.item_name)?`<button class="btn small" data-veh-bag="${i.id}" ${n(i.quantity)<=0?'disabled':''}>+ Bolsa</button>`:''}</div></td></tr>`).join('')}</tbody></table></div>`;
  restockVehicleBag.onclick=()=>nui('vehicleEquipmentRestockBag',{vehicleNetId:n(d.vehicleNetId),departmentId:n(d.departmentId)});
  vehicleEquipRefresh.onclick=()=>nui('vehicleEquipmentRefresh',{vehicleNetId:n(d.vehicleNetId),departmentId:n(d.departmentId)});
  content.querySelectorAll('[data-veh-take]').forEach(b=>b.onclick=()=>nui('vehicleEquipmentTake',{vehicleNetId:n(d.vehicleNetId),departmentId:n(d.departmentId),supplyId:n(b.dataset.vehTake),count:1}));
  content.querySelectorAll('[data-veh-bag]').forEach(b=>b.onclick=()=>nui('vehicleEquipmentLoadBag',{vehicleNetId:n(d.vehicleNetId),departmentId:n(d.departmentId),supplyId:n(b.dataset.vehBag),count:1}));
}

function pageGarage(){
  nav([['os','⌂','Inicio'],['garage','▣','Garagem']],state.context);const d=state.department;
  const stretcherModel=d?.settings?.defaultStretcherModel||state.bootstrap?.config?.stretcher?.defaultModel||'strykerpro';
  const vehicles=d?.vehicles||[];
  const rows=[`<div class="garage-runtime-row"><div class="garage-runtime-main"><span class="garage-runtime-icon">✚</span><div><span class="pill">Equipamento</span><h3>Maca Stryker Pro</h3><small>${esc(stretcherModel)}</small></div></div><div class="garage-runtime-actions"><button class="btn primary" id="spawnStretcher">Retirar</button><button class="btn" id="storeStretcher">Guardar</button></div></div>`,...vehicles.map(v=>`<div class="garage-runtime-row"><div class="garage-runtime-main"><span class="garage-runtime-icon">🚑</span><div><span class="pill">Viatura · Level ${v.min_level}</span><h3>${esc(v.label)}</h3><small>${esc(v.model)}</small></div></div><div class="garage-runtime-actions"><button class="btn primary" data-spawn-id="${v.id}">Retirar</button><button class="btn" data-store-model="${esc(v.model)}">Guardar</button></div></div>`)].join('');
  const emptyNotice=vehicles.length?``:`<div class="garage-empty-warning"><b>Catalogo de viaturas ainda nao foi hidratado.</b><span>O FiveEMS esta consultando o departamento desta garagem. Se continuar vazio, confira Creator → Veiculos.</span></div>`;
  content.innerHTML=title('Garagem EMS','Retire ou guarde viaturas e equipamentos no mesmo catalogo.')+emptyNotice+`<div class="garage-runtime-list">${rows}</div>`;
  content.querySelectorAll('[data-spawn-id]').forEach(b=>b.onclick=async()=>{
    const result=await nui('spawnVehicle',{vehicleId:Number(b.dataset.spawnId),garagePointId:Number(state.extra?.pointId)||null});
    if(result?.ok!==false) close();
  });
  content.querySelectorAll('[data-store-model]').forEach(b=>b.onclick=()=>nui('storeVehicle',{model:b.dataset.storeModel}));
  spawnStretcher.onclick=async()=>{
    const result=await nui('spawnStretcher');
    if(result?.ok!==false) close();
  };
  storeStretcher.onclick=()=>nui('storeStretcher');
}

function pageStock(){
  nav([['os','⌂','Inicio'],['stock','▦','Estoque']],state.context);const d=state.department;
  content.innerHTML=title('Medicamentos e Equipamentos','Catalogo operacional do FiveEMS.')+`<div class="table-wrap"><table><thead><tr><th>Item</th><th>Categoria</th><th>Qtd</th><th>Level</th><th>Restricao</th></tr></thead><tbody>${(d?.supplies||[]).map(s=>`<tr><td>${esc(s.label)}</td><td>${esc(s.category)}</td><td>${s.quantity}</td><td>${s.min_level}</td><td>${s.advanced?'<span class="pill warn">Avancado</span>':'Basico'} <button class="btn small" data-take-supply="${s.id}">Pegar 1</button></td></tr>`).join('')}</tbody></table></div><p class="label">Nesta fundacao o estoque e persistente no banco; adaptadores de inventario serao expandidos na proxima etapa.</p>`;
  content.querySelectorAll('[data-take-supply]').forEach(b=>b.onclick=()=>nui('takeSupply',{supplyId:Number(b.dataset.takeSupply),count:1}));
}
function pageDirector(){
  nav([['director','♜','Mesa do Diretor']],state.context);const d=state.department;
  content.innerHTML=title('Mesa da Direcao','Gestao de equipe e cargos.')+`<div class="grid two"><div class="card"><h3>Atribuir player</h3>${field('Server ID','memberId','', 'number')}${selectField('Cargo','memberRank',(d?.ranks||[]).map(r=>[r.id,`${r.name} (${r.grade})`]),'')}<button class="btn primary" id="assign">Atribuir ao departamento</button></div><div class="card"><h3>Departamento</h3><p>${esc(d?.name||'---')}</p><p>${esc(d?.type||'')}</p></div></div>`;
  assign.onclick=()=>nui('assignMember',{targetServerId:n(memberId.value),departmentId:d?.id,rankId:n(memberRank.value)});
}
function pageCSI(){
  nav([['os','⌂','Inicio'],['csi','⌕','CSI'],['stock','▦','Estoque']],state.context);
  const e=state.extra?.evidence||state.csiEvidence||state.csiLabResult;
  let html=title('Policia Cientifica / CSI','Documentacao, coleta, cadeia de custodia e analise laboratorial.');
  if(e){
    const analysisHtml=e.analysis
      ? `<p><b>Familia compativel:</b> ${esc(e.analysis.instrumentFamily)}</p><p>${esc(e.analysis.conclusion)}</p><p>Confianca do mecanismo de gameplay: ${Math.round(n(e.analysis.confidence)*100)}%</p>`
      : '<p>A analise e liberada depois da coleta e cadeia de custodia.</p>';
    const chainHtml=(e.chain||[]).map(c=>`<p>${new Date((c.at||0)*1000).toLocaleString()} · ${esc(c.action)} · ${esc(c.by||'')}</p>`).join('')||'Sem movimentacoes.';
    html+=`<div class="grid two"><div class="csi-evidence"><div class="label">Evidencia #${e.id}</div><h3>${esc(e.type||'trace')}</h3><p>Regiao: ${esc(e.region||'---')}</p><p>Categoria de trauma: ${esc(e.category||'unknown')}</p><p>Estado: <span class="pill">${esc(e.state||'scene')}</span></p><p>${esc(e.inference||'')}</p><div class="row"><button class="btn primary" id="collectE">Fotografar / coletar / lacrar</button><button class="btn blue" id="analyzeE">Analisar no laboratorio</button></div></div><div class="card"><h3>Laudo preliminar</h3>${analysisHtml}<h3>Cadeia de custodia</h3><div class="chain">${chainHtml}</div></div></div>`;
  } else {
    html+=`<div class="grid three"><div class="card"><h3>Processar cena</h3><p>Marcar, fotografar, medir e coletar vestigios.</p></div><div class="card"><h3>Laboratorio</h3><p>Analise de material biologico, ferimentos e compatibilidade do instrumento.</p></div><div class="card"><h3>Cadeia de custodia</h3><p>Envelope/lacre, coletor, transferencias e laudo.</p></div></div><div class="spacer"></div><div class="card"><h3>Criar caso</h3>${field('Titulo do caso','caseTitle','Ocorrencia pericial')}<div class="field"><label>Resumo da cena</label><textarea id="caseSummary"></textarea></div><button class="btn primary" id="createCase">Abrir caso</button></div>`;
  }
  content.innerHTML=html;
  if(e){
    collectE.onclick=()=>nui('csiCollect',{evidenceId:e.id,notes:'Coleta documentada pelo painel FiveEMS'});
    analyzeE.onclick=()=>nui('csiAnalyze',{evidenceId:e.id});
  } else {
    createCase.onclick=()=>nui('csiCreateCase',{title:caseTitle.value,summary:caseSummary.value});
  }
}
function desktopWindowTitle(app){
  return {
    settings:'Configuracoes do Sistema',
    patient:'Prontuario / ePCR',
    calls:'Central de Ocorrencias',
    stock:'Estoque Clinico',
    chat:'Comunicacao Interna',
    csi:'Policia Cientifica / CSI',
    reports:'Relatorios',
  }[app] || 'Aplicativo';
}

function desktopWindowBody(app){
  const member=state.bootstrap?.member||{};
  const d=state.department||{};
  const supplies=(d.supplies||[]).slice(0,6);
  const s=state.targetState?.state||state.targetState||null;
  const v=s?.vitals||{};
  if(app==='settings'){
    return `<div class="settings-shell"><aside class="settings-menu"><div class="settings-cap">Control Panel</div><h2>Settings</h2><small>computer medical system</small><button class="settings-link active">Appearance</button><button class="settings-link">Widgets</button><button class="settings-link">Controls</button><button class="settings-link">Language</button><button class="settings-link">About</button><div class="settings-foot">FiveEMS Medical OS<br>v0.4.3</div></aside><section class="settings-main"><div class="settings-head"><div><div class="eyebrow">Appearance</div><h1>Computer Medical OS</h1><p>Visual inspirado em sistema operacional, com desktop, dock e janelas para uso hospitalar.</p></div><span class="live-dot">LIVE</span></div><div class="settings-grid"><div class="wallpaper-card wallpaper-a"><span>Workspace</span><b>${esc(member.department_name||'FiveEMS')}</b></div><div class="wallpaper-card wallpaper-b"><span>Status</span><b>${member.on_duty?'Em servico':'Fora de servico'}</b></div><div class="wallpaper-card wallpaper-c"><span>Usuario</span><b>${esc(member.display_name||'Sem login')}</b></div><div class="wallpaper-card wallpaper-d"><span>Monitor</span><b>Separado do computador</b></div></div><div class="settings-split"><div class="mini-panel"><div class="eyebrow">Workspace</div><h3>Preferencias rapidas</h3><p>Departamento: ${esc(d.name||'Nao atribuido')}</p><p>Tipo: ${esc(d.type||'---')}</p><p>Cargo: ${esc(member.rank_name||'Sem cargo')}</p></div><div class="mini-panel"><div class="eyebrow">Apps</div><h3>Fluxo principal</h3><p>O computador compartilha os mesmos softwares do tablet: prontuario, ocorrencias, estoque, comunicacao, CSI e relatorios.</p></div></div></section></div>`;
  }
  if(app==='patient'){
    return `<div class="os-app-pane"><div class="os-app-hero"><div><div class="eyebrow">Patient Workspace</div><h2>Prontuario / ePCR</h2><p>Atendimento clinico, sinais vitais, tratamentos, oxigenio e relatorio pos-atendimento.</p></div><div class="row"><button class="btn primary" data-open-workspace="patient">Abrir workspace clinico</button></div></div>${s ? `${vitalsBlock(v)}<div class="spacer"></div><div class="grid two"><div class="card"><h3>Paciente carregado</h3><p>Server ID: ${esc(state.targetServerId||'---')}</p><p>Hemorragia: ${Math.round(n(s.totalBleeding||0)*10)/10}</p><p>Dor: ${Math.round(n(s.pain||0))}</p></div><div class="card"><h3>Acoes rapidas</h3><div class="row"><button class="btn blue" data-open-workspace="monitor">Abrir monitor</button><button class="btn" data-open-workspace="patient">Reabrir prontuario</button></div></div></div>` : `<div class="card"><h3>Nenhum paciente carregado</h3><p>Use <b>/fiveemsexam</b> ou <b>/fiveemspatient &lt;id&gt;</b> para abrir o atendimento completo. Depois, o resumo aparecera aqui.</p></div>`}`;
  }
  if(app==='calls'){
    return `<div class="os-app-pane"><div class="os-app-hero"><div><div class="eyebrow">Dispatch</div><h2>Central de Ocorrencias</h2><p>Gestao operacional de chamados EMS e hospitalares.</p></div></div><div class="grid two"><div class="card"><h3>Despacho</h3><p>Use o comando de emergencia configurado pelo Admin para gerar um chamado na sua posicao.</p></div><div class="card"><h3>Status</h3><p>Modulo pronto para receber lista de chamadas, aceite e andamento na proxima etapa.</p></div></div></div>`;
  }
  if(app==='stock'){
    return `<div class="os-app-pane"><div class="os-app-hero"><div><div class="eyebrow">Inventory</div><h2>Estoque Clinico</h2><p>Medicamentos, equipamentos e materiais do departamento.</p></div></div><div class="table-wrap"><table><thead><tr><th>Item</th><th>Categoria</th><th>Qtd</th><th>Level</th></tr></thead><tbody>${supplies.map(s=>`<tr><td>${esc(s.label)}</td><td>${esc(s.category)}</td><td>${n(s.quantity)}</td><td>${n(s.min_level,1)}</td></tr>`).join('') || '<tr><td colspan="4">Nenhum item cadastrado.</td></tr>'}</tbody></table></div></div>`;
  }
  if(app==='chat'){
    return `<div class="os-app-pane"><div class="os-app-hero"><div><div class="eyebrow">Internal Comms</div><h2>Comunicacao Interna</h2><p>Mensageria para medicos, enfermeiros, socorristas e equipes do departamento.</p></div></div><div class="grid two"><div class="card"><h3>Canal operacional</h3><p>Planejado para integracao com setores, plantao e repasse de pacientes.</p></div><div class="card"><h3>Mensagem do sistema</h3><p>Nenhuma nova mensagem.</p></div></div></div>`;
  }
  if(app==='csi'){
    return `<div class="os-app-pane"><div class="os-app-hero"><div><div class="eyebrow">Forensics</div><h2>Policia Cientifica / CSI</h2><p>Cadeia de custodia, laboratorio e laudos periciais.</p></div><div class="row"><button class="btn primary" data-open-workspace="csi">Abrir modulo CSI</button></div></div><div class="grid three"><div class="card"><h3>Vestigios</h3><p>Coleta, fotografia e lacre.</p></div><div class="card"><h3>Laboratorio</h3><p>Analises de compatibilidade e materiais biologicos.</p></div><div class="card"><h3>Casos</h3><p>Laudos, historico e cadeia de custodia persistente.</p></div></div></div>`;
  }
  if(app==='reports'){
    return `<div class="os-app-pane"><div class="os-app-hero"><div><div class="eyebrow">Documents</div><h2>Relatorios</h2><p>ePCR, laudos e documentacao do FiveEMS.</p></div></div><div class="grid two"><div class="card"><h3>Relatorio clinico</h3><p>Baseado na ficha de trauma e nas etapas de atendimento definidas para o FiveEMS.</p></div><div class="card"><h3>Producao</h3><p>XP por relatorio, transferencia e atendimentos concluidos.</p></div></div></div>`;
  }
  return `<div class="card">Aplicativo em construcao.</div>`;
}

function pageComputer(){
  sidebar.innerHTML='';
  if(!state.desktopWindows.length) openOSApp('desktop','finder');
  content.innerHTML = renderOSStage('desktop');
  attachOSInteractions('desktop');
}

function pageTablet(){
  sidebar.innerHTML='';
  if(!state.tabletWindows.length) openOSApp('tablet','finder');
  content.innerHTML = renderOSStage('tablet');
  attachOSInteractions('tablet');
}

function pageSimple(kind){
  nav([['os','⌂','Launcher'],[kind,'▤',kind]],state.context);
  const titles={calls:'Ocorrencias',chat:'Comunicacao Interna',reports:'Relatorios'};
  const notes={calls:'Fila de ocorrencias, despacho e acompanhamento operacional.',chat:'Mensageria interna entre medicos, enfermeiros, socorristas e setores.',reports:'Central de relatorios, laudos e documentos do FiveEMS.'};
  content.innerHTML=title(titles[kind]||kind,'Modulo operacional FiveEMS.')+`<div class="os-window"><div class="window-bar">FiveEMS ${esc(titles[kind]||kind)}</div><div class="window-content"><p>${esc(notes[kind]||'Modulo operacional.')}</p><p>Este modulo continua separado do monitor multiparametrico e dos paineis administrativos.</p></div></div>`;
}

function render(){
  if(!state.open)return;
  const body=document.querySelector('.device-body');
  const osMode = (state.context==='computer' || state.context==='tablet');
  const clinicalSceneMode = state.context==='patient' && state.patientView==='scene';
  root.classList.toggle('os-transparent', osMode);
  root.classList.toggle('clinical-scene-mode', clinicalSceneMode);
  root.classList.toggle('monitor-live-mode', state.context==='monitor' || state.context==='overlay');
  frame.className='device';
  frame.classList.toggle('scene-audit-shell', clinicalSceneMode);
  frame.classList.toggle('tablet', state.context==='tablet');
  frame.classList.toggle('computer-os-shell', state.context==='computer');
  frame.classList.toggle('tablet-os-shell', state.context==='tablet');
  frame.classList.toggle('creator-shell', state.context==='creator');
  frame.classList.toggle('monitor-device-shell', state.context==='monitor');
  frame.classList.toggle('bed-chart-device', state.context==='bed_chart');
  frame.style.display = state.context==='overlay' ? 'none' : '';
  touchFinger.classList.toggle('hidden',state.context!=='tablet');
  const labels={os:'LAUNCHER',admin:'ADMIN',creator:'CRIADOR',director:'DIRETORIA',computer:'COMPUTADOR',tablet:'TABLET',monitor:'MONITOR',overlay:'MONITOR',patient:'PACIENTE',stock:'ESTOQUE',garage:'GARAGEM',csi:'CSI',calls:'OCORRENCIAS',chat:'COMUNICACAO',reports:'RELATORIOS',field_bag:'BOLSA MEDICA',vehicle_equipment:'EQUIP. VIATURA',bed_chart:'FICHA DO LEITO'};
  contextBadge.textContent=labels[state.context]||String(state.context||'').toUpperCase();
  const wideContext=(state.context==='computer' || state.context==='tablet' || state.context==='creator' || state.context==='monitor' || state.context==='overlay' || state.context==='field_bag' || state.context==='vehicle_equipment' || state.context==='bed_chart' || clinicalSceneMode);
  body.style.gridTemplateColumns = wideContext ? '1fr' : '';
  sidebar.style.display = wideContext ? 'none' : '';
  content.style.padding = (state.context==='computer' || state.context==='tablet' || state.context==='monitor' || state.context==='overlay' || state.context==='bed_chart' || clinicalSceneMode) ? '0' : '';
  content.style.overflow = (state.context==='computer' || state.context==='tablet' || state.context==='overlay' || state.context==='bed_chart' || clinicalSceneMode) ? 'hidden' : '';
  clearInterval(waveTimer);clearInterval(sceneWaveTimer);
  if(state.context!=='monitor' && !monitorOverlayActive()){clearMonitorAudioTimers();}
  setTimeout(renderMonitorOverlay,0);
  if(state.context==='overlay'){renderMonitorOverlay();return;}
  if(state.context==='admin')return pageAdmin();
  if(state.context==='creator')return pageDepartmentCreator();
  if(state.context==='os')return pageOS();
  if(state.context==='patient')return clinicalSceneMode?pagePatientScene():pagePatient();
  if(state.context==='bed_chart')return pageBedChart();
  if(state.context==='monitor')return pageMonitor();
  if(state.context==='field_bag')return pageFieldBag();
  if(state.context==='vehicle_equipment')return pageVehicleEquipment();
  if(state.context==='garage')return pageGarage();
  if(state.context==='stock')return pageStock();
  if(state.context==='director')return pageDirector();
  if(state.context==='csi')return pageCSI();
  if(state.context==='computer')return pageComputer();
  if(state.context==='tablet')return pageTablet();
  if(['calls','chat','reports'].includes(state.context))return pageSimple(state.context);
  return pageOS();
}

window.addEventListener('message',e=>{
  const {action,data}=e.data||{};
  if(action==='open'){
    closeInProgress=false;state.open=true;state.context=data?.context||'os';state.extra=data?.extra||{};
    state.targetRef=state.extra.targetRef||state.targetRef;state.targetServerId=state.extra.targetServerId||state.targetServerId;
    if(state.extra?.portableMonitorNetId)state.monitorPortableNetId=Number(state.extra.portableMonitorNetId);
    state.clinicalMarkerSmoothed={};state.clinicalLabelSides={};
    if(state.context==='patient'){state.patientView='scene';state.clinicalRegion=null;state.clinicalSceneActive=false;}
    if(state.context==='bed_chart'){state.bedChart=null;state.bedChartTab='summary';}
    root.style.pointerEvents='';root.classList.remove('hidden');frame.style.display='';render();
  }
  if(action==='close'){
    closeInProgress=false;state.open=false;state.clinicalSceneActive=false;state.clinicalMarkerPositions={};state.clinicalMarkerSmoothed={};state.clinicalLabelSides={};
    state.monitorOverlay.enabled=false;state.monitorTargetState=null;state.monitorTargetRef=null;state.monitorPortableNetId=null;
    hardHideFiveEMS();clearInterval(waveTimer);clearInterval(sceneWaveTimer);clearInterval(monitorOverlayWaveTimer);monitorOverlayWaveTimer=null;clearMonitorAudioTimers();
  }
  if(action==='monitorOverlayOnly'){
    state.open=true;state.context='overlay';root.classList.remove('hidden');root.style.pointerEvents='none';frame.style.display='none';renderMonitorOverlay();
  }
  if(action==='monitorOverlayFocus'){
    state.open=true;state.context='overlay';root.classList.remove('hidden');root.style.pointerEvents='';frame.style.display='none';renderMonitorOverlay();
  }
  if(action==='bootstrap'){state.bootstrap=data;state.department=data?.department||state.department;if(state.extra?.targetServerId){state.targetServerId=Number(state.extra.targetServerId);}render();}
  if(action==='garageCatalog'){state.department=data;if(state.bootstrap)state.bootstrap.department=data;if(state.context==='garage')render();}
  if(action==='department'){state.department=data;if(state.bootstrap)state.bootstrap.department=data;render();}
  if(action==='departmentSaved'){state.department=data;if(state.bootstrap){state.bootstrap.department=data;state.bootstrap.departments=state.bootstrap.departments||[];const i=state.bootstrap.departments.findIndex(x=>Number(x.id)===Number(data.id));if(i>=0)state.bootstrap.departments[i]=data;else state.bootstrap.departments.push(data);}if(state.context==='creator'&&state.creatorView==='list'){state.creatorSelectedId=null;}render();}
  if(action==='departmentDeleted'){const id=Number(data?.id);if(state.bootstrap){state.bootstrap.departments=(state.bootstrap.departments||[]).filter(x=>Number(x.id)!==id);if(state.bootstrap.department&&Number(state.bootstrap.department.id)===id)state.bootstrap.department=null;}if(state.department&&Number(state.department.id)===id)state.department=null;state.creatorView='list';state.creatorSelectedId=null;toast('Departamento excluido com sucesso.');render();}
  if(action==='departmentDeleteFailed'){toast(data?.message||'Nao foi possivel excluir o departamento.');}
  if(action==='targetMedicalState'){state.targetServerId=Number(data?.targetServerId);state.targetState=data?.state;render();}
  if(action==='monitorDetached'){state.targetRef=null;state.targetServerId=null;state.targetState=null;if(state.context==='monitor')render();}
  if(action==='portableMonitorDetached'){
    state.monitorOverlay.enabled=false;state.monitorTargetState=null;state.monitorTargetRef=null;state.monitorPortableNetId=null;
    clearMonitorAudioTimers();clearInterval(monitorOverlayWaveTimer);monitorOverlayWaveTimer=null;
    if(state.context==='overlay'){state.open=false;hardHideFiveEMS();}else render();
    if(data?.reason)toast(data.reason);
  }
  if(action==='portableMonitorRemoved'){
    state.monitorOverlay.enabled=false;state.monitorTargetState=null;state.monitorTargetRef=null;state.monitorPortableNetId=null;
    clearMonitorAudioTimers();clearInterval(monitorOverlayWaveTimer);monitorOverlayWaveTimer=null;
    if(state.context==='overlay'){state.open=false;hardHideFiveEMS();}else render();
  }
  if(action==='bedChartData'){
    state.bedChart=data||null;
    state.targetRef=data?.targetRef||state.targetRef;
    state.targetServerId=state.targetRef?.kind==='player'?Number(state.targetRef.serverId):null;
    state.targetState=data?.state||null;
    state.clinicalCatalog=data?.clinicalCatalog||state.clinicalCatalog;
    state.treatmentCatalog=data?.treatmentCatalog||state.treatmentCatalog;
    if(state.context==='bed_chart')render();
  }
  if(action==='clinicalState'){
    state.targetRef=data?.targetRef||state.targetRef;
    state.targetServerId=state.targetRef?.kind==='player'?Number(state.targetRef.serverId):null;
    state.targetState=data?.state||null;
    state.medicalBag=data?.bag||state.medicalBag||{};
    state.clinicalCatalog=data?.clinicalCatalog||state.clinicalCatalog;
    state.treatmentCatalog=data?.treatmentCatalog||state.treatmentCatalog;
    if(state.bootstrap){state.bootstrap.medicalBag=state.medicalBag;state.bootstrap.clinicalCatalog=state.clinicalCatalog;state.bootstrap.treatments=state.treatmentCatalog||state.bootstrap.treatments;}
    render();
  }
  if(action==='monitorState'){
    state.monitorTargetRef=data?.targetRef||state.monitorTargetRef;
    state.monitorTargetState=data?.state||null;
    if(state.context==='monitor'){
      state.targetRef=state.monitorTargetRef;
      state.targetServerId=state.targetRef?.kind==='player'?Number(state.targetRef.serverId):null;
      state.targetState=state.monitorTargetState;
      render();
    }
    if(state.monitorOverlay?.enabled){
      renderMonitorOverlay();
      restartMonitorBeep((state.monitorTargetState?.state||state.monitorTargetState||{}).vitals||{});
    }
    if(state.context==='monitor' && state.extra?.openMode==='overlay' && state.monitorTargetState){
      state.extra.openMode=null;
      minimizeMonitorToOverlay();
    }
  }
  if(action==='clinicalSceneMarkers'){state.clinicalMarkerPositions=data?.markers||{};updateClinicalSceneMarkers();}
  if(action==='fieldBagData'){state.extra=data||{};if(state.context==='field_bag')render();}
  if(action==='vehicleEquipmentData'){state.extra=data||{};if(state.context==='vehicle_equipment')render();}
  if(action==='medicalBag'){state.medicalBag=data||{};if(state.bootstrap)state.bootstrap.medicalBag=state.medicalBag;if(state.context==='patient')render();}
  if(action==='selfMedicalState'){if(state.context==='monitor'&&!state.targetState)state.targetState=data;}
  if(action==='defibAnalysis'){state.defib={rhythm:data?.rhythm||'--',shockable:!!data?.shockable};render();}
  if(action==='adminSettings'){state.settings=data||{};render();}
  if(action==='runtimeCommandsConfig'){
    state.bootstrap=state.bootstrap||{}; state.bootstrap.config=state.bootstrap.config||{};
    state.bootstrap.config.commands=data||{};
    if(state.context==='admin') render();
  }
  if(action==='runtimeStretcherConfig'){
    state.bootstrap=state.bootstrap||{};
    state.bootstrap.config=state.bootstrap.config||{};
    state.bootstrap.config.stretcher=data||{};
    if(state.context==='admin') render();
  }
  if(action==='csiEvidenceUpdated'){state.csiEvidence=data;state.extra={...state.extra,evidence:data};render();}
  if(action==='csiLabResult'){state.csiLabResult=data;state.extra={...state.extra,evidence:data};render();}
  if(action==='setContext'){setContext(data?.context||'os',data||{});}
  if(action==='xpUpdated')toast(`+${data?.amount||0} XP`);
});
