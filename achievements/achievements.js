const db = window.SCHOOL_SUPABASE;
let items = [];

function esc(value='') {
  return String(value).replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
}

async function loadFallback() {
  const r = await fetch('../assets/default-data.json');
  const data = await r.json();
  return {
    settings: data,
    achievements: (data.achievements || []).map((x, i) => ({...x, image_url:x.img, description:'', created_at:new Date(Date.now()-i*1000).toISOString()}))
  };
}

async function init() {
  let settings, achievements;
  try {
    const fallback = await loadFallback();
    settings = fallback.settings;
    achievements = fallback.achievements;
    if (db) {
      const [s, a] = await Promise.all([
        db.from('site_settings').select('data').eq('id',1).maybeSingle(),
        db.from('achievements').select('id,title,year,image_url,description,created_at').eq('published',true).order('created_at',{ascending:false})
      ]);
      if (s.data?.data) settings = {...settings, ...s.data.data};
      if (Array.isArray(a.data)) achievements = a.data;
    }
  } catch (e) { console.error(e); }

  document.getElementById('school-name').textContent = settings?.info?.nameTh || 'โรงเรียนวัดหนองแวงวิทยา';
  const logo = settings?.branding?.logoUrl;
  if (logo) { const img=document.getElementById('site-logo'); img.src=logo; img.classList.remove('hidden'); document.getElementById('site-logo-icon').classList.add('hidden'); }
  items = achievements || [];
  buildYearFilter(); render(); lucide.createIcons();
}

function buildYearFilter() {
  const select = document.getElementById('year-filter');
  [...new Set(items.map(x => x.year).filter(Boolean))].sort((a,b)=>String(b).localeCompare(String(a),'th')).forEach(y => select.insertAdjacentHTML('beforeend',`<option value="${esc(y)}">ปี ${esc(y)}</option>`));
}

function render() {
  const q = document.getElementById('search').value.trim().toLowerCase();
  const year = document.getElementById('year-filter').value;
  const filtered = items.filter(x => (!q || (x.title||'').toLowerCase().includes(q) || (x.description||'').toLowerCase().includes(q)) && (year==='all' || String(x.year)===year));
  const status = document.getElementById('status'), grid = document.getElementById('grid');
  if (!filtered.length) { grid.classList.add('hidden'); status.classList.remove('hidden'); status.textContent='ไม่พบผลงานที่ตรงกับเงื่อนไข'; return; }
  status.classList.add('hidden'); grid.classList.remove('hidden');
  grid.innerHTML = filtered.map(x => `<article class="glass rounded-[2rem] overflow-hidden group hover:-translate-y-1 hover:shadow-xl transition-all"><div class="aspect-[4/3] bg-slate-100 overflow-hidden relative"><img src="${esc(x.image_url||x.img||'')}" alt="${esc(x.title)}" class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500" loading="lazy"><span class="absolute top-3 right-3 bg-orange-500/90 text-white text-xs font-bold px-3 py-1 rounded-full backdrop-blur">ปี ${esc(x.year||'-')}</span></div><div class="p-5"><h3 class="font-bold text-slate-900 leading-relaxed">${esc(x.title)}</h3>${x.description?`<p class="text-sm text-slate-500 mt-3 leading-relaxed">${esc(x.description)}</p>`:''}</div></article>`).join('');
}

document.getElementById('search').addEventListener('input', render);
document.getElementById('year-filter').addEventListener('change', render);
init();
