
(()=>{
'use strict';
const cfg=window.AW_MODULE_CONFIG||{};
const frame=document.getElementById('legacyFrame');
const loading=document.getElementById('moduleLoading');
const tabs=[...document.querySelectorAll('[data-aw-section]')];
let current=(new URLSearchParams(location.search).get('tab')||cfg.defaultSection||tabs[0]?.dataset.awSection||'dashboard');
let activationTimer=null;
let activationAttempts=0;

function setActive(section){
  current=section;
  tabs.forEach(b=>b.classList.toggle('active',b.dataset.awSection===section));
  try{
    const u=new URL(location.href);
    u.searchParams.set('tab',section);
    history.replaceState({},'',u);
  }catch(_){}
}
function injectEmbedStyle(doc){
  if(!doc||doc.getElementById('aw-v28-embed-style'))return;
  const st=doc.createElement('style');
  st.id='aw-v28-embed-style';
  st.textContent=`
    .manager-topbar,.manager-sidebar{display:none!important}
    .manager-shell{grid-template-columns:minmax(0,1fr)!important;min-height:100vh!important}
    .manager-content{max-width:none!important;width:100%!important;padding:14px!important}
    #app{min-height:100vh!important}
    body{background:#fff!important}
  `;
  doc.head?.appendChild(st);
}
function activateInside(section){
  try{
    const doc=frame.contentDocument;
    if(!doc)return false;
    injectEmbedStyle(doc);

    // If login is visible, leave it intact. After login the polling below will retry.
    const login=doc.getElementById('login');
    const app=doc.getElementById('app');
    const appVisible=app&&!app.classList.contains('hidden');
    if(!appVisible && login && !login.classList.contains('hidden')) return false;

    const nav=doc.querySelector(`[data-section="${CSS.escape(section)}"]`);
    const sec=doc.getElementById('section-'+section);
    if(nav){
      try{nav.click()}catch(_){}
    }
    if(sec){
      // Fallback if legacy router did not activate the requested section.
      doc.querySelectorAll('.section').forEach(x=>x.classList.remove('active'));
      sec.classList.add('active');
      try{sec.scrollIntoView({block:'start'})}catch(_){}
      return true;
    }
  }catch(e){
    console.warn('[V28 module shell] activate',e);
  }
  return false;
}
function beginActivation(section){
  clearInterval(activationTimer);
  activationAttempts=0;
  if(loading)loading.style.display='grid';
  const run=()=>{
    activationAttempts++;
    const ok=activateInside(section);
    if(ok){
      clearInterval(activationTimer);
      activationTimer=null;
      if(loading)loading.style.display='none';
    }else if(activationAttempts>80){
      clearInterval(activationTimer);
      activationTimer=null;
      if(loading){
        loading.innerHTML='<div><b>ไม่สามารถเปิดโมดูลอัตโนมัติได้</b><br><span style="color:#94a3b8">ลองกดรีเฟรช หรือเปิด Legacy Manager</span></div>';
      }
    }
  };
  run();
  activationTimer=setInterval(run,250);
}
function loadSection(section){
  setActive(section);
  if(!frame.src || !frame.dataset.loaded){
    frame.dataset.loaded='1';
    frame.src=`../legacy.html?embed=1&section=${encodeURIComponent(section)}`;
  }else{
    beginActivation(section);
  }
}
tabs.forEach(b=>b.addEventListener('click',()=>loadSection(b.dataset.awSection)));
frame?.addEventListener('load',()=>beginActivation(current));

document.getElementById('moduleRefresh')?.addEventListener('click',()=>{
  if(frame?.contentWindow)frame.contentWindow.location.reload();
});
document.getElementById('moduleLegacy')?.addEventListener('click',()=>{
  location.href=`../legacy.html?section=${encodeURIComponent(current)}`;
});
document.getElementById('moduleHub')?.addEventListener('click',()=>location.href='../');

setActive(current);
loadSection(current);
})();
