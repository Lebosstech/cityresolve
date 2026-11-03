// Page publique CityResolve : signalement + carte + suivi (données réelles filtrées).
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const isMediaId = (s) => /^[0-9a-f]{24}$/.test(String(s || ''));
const state = { x: null, y: null, mediaId: null };

async function api(path, method = 'GET', body = null) {
  const r = await fetch(path, { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : null });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || ('HTTP ' + r.status));
  return j;
}

// --- Navigation ---
document.querySelectorAll('[data-nav]').forEach((a) => {
  a.onclick = (e) => {
    e.preventDefault();
    document.querySelectorAll('.nav-links a').forEach((x) => x.classList.remove('active'));
    document.querySelectorAll('.view').forEach((v) => v.classList.remove('active'));
    const v = a.dataset.nav;
    document.querySelector(`.nav-links a[data-nav="${v}"]`)?.classList.add('active');
    $('view-' + (v === 'home' ? 'home' : v)).classList.add('active');
    if (a.dataset.scroll) document.getElementById(a.dataset.scroll)?.scrollIntoView({ behavior: 'smooth' });
    else window.scrollTo({ top: 0 });
  };
});
$('mapBig').onclick = (e) => { e.preventDefault(); $('mapCard').classList.toggle('large'); document.getElementById('mapCard').scrollIntoView({ behavior: 'smooth' }); };
$('recentAll').onclick = (e) => { e.preventDefault(); loadRecent(10); };

// --- Formulaire ---
$('pText').oninput = () => { $('pCount').textContent = $('pText').value.length; };
document.querySelectorAll('.tile').forEach((t) => {
  t.onclick = () => {
    $('pCat').value = t.dataset.cat;
    $('formCard').scrollIntoView({ behavior: 'smooth' });
  };
});
function showErr(m) { const b = $('pErr'); b.textContent = m; b.hidden = false; }
function clearErr() { $('pErr').hidden = true; $('pErr').textContent = ''; }
$('pFile').onchange = async () => {
  clearErr();
  const f = $('pFile').files[0];
  if (!f) return;
  if (f.size > 5 * 1024 * 1024) { showErr('Photo trop volumineuse : ' + f.size + ' octets (max 5 Mo).'); $('pFile').value = ''; return; }
  try {
    const r = await fetch('/api/photos', { method: 'POST', headers: { 'Content-Type': f.type || 'application/octet-stream' }, body: f });
    const j = await r.json();
    if (!r.ok) throw new Error(j.error || ('HTTP ' + r.status));
    state.mediaId = j.mediaId;
    $('pMedia').textContent = 'Photo téléversée (' + j.size + ' octets, ' + j.mime + ').';
    $('pImg').src = '/api/photos/' + j.mediaId;
    $('pPreview').hidden = false;
  } catch (e) { showErr(e.message); $('pFile').value = ''; }
};
$('pRemove').onclick = () => { state.mediaId = null; $('pFile').value = ''; $('pPreview').hidden = true; $('pMedia').textContent = ''; };
$('pPick').onclick = () => { $('pickModal').hidden = false; drawPicker(); };
$('pickCancel').onclick = () => { $('pickModal').hidden = true; };
$('pickOk').onclick = () => {
  if (state.x === null) { showErr('Cliquez sur la grille pour choisir une position.'); return; }
  $('pCoords').textContent = `Position : (${state.x.toFixed(1)}, ${state.y.toFixed(1)}) km — grille fictive`;
  $('pickModal').hidden = true;
  drawMap();
};
function drawPicker() {
  const svg = $('pickMap');
  let h = '';
  for (let i = 0; i <= 5; i++) {
    h += `<line x1="${20 + i * 80}" y1="20" x2="${20 + i * 80}" y2="420" stroke="#e2e8f0"/>`;
    h += `<line x1="20" y1="${20 + i * 80}" x2="420" y2="${20 + i * 80}" stroke="#e2e8f0"/>`;
  }
  svg.innerHTML = h + '<circle id="pickDot" r="9" fill="#0b5fff" hidden/>';
  svg.onclick = (e) => {
    const r = svg.getBoundingClientRect();
    const px = (e.clientX - r.left) / r.width * 440, py = (e.clientY - r.top) / r.height * 440;
    state.x = Math.min(5, Math.max(0, (px - 20) / 80));
    state.y = Math.min(5, Math.max(0, 5 - (py - 20) / 80));
    state.x = Math.round(state.x * 10) / 10; state.y = Math.round(state.y * 10) / 10;
    const d = svg.querySelector('#pickDot');
    d.setAttribute('cx', 20 + state.x * 80); d.setAttribute('cy', 20 + (5 - state.y) * 80);
    d.hidden = false;
  };
}
$('pSend').onclick = async () => {
  clearErr();
  $('pConfirm').hidden = true;
  const text = $('pText').value.trim();
  if (!text) return showErr('Décrivez le problème observé.');
  if (text.length > 500) return showErr('Description trop longue (' + text.length + '/500).');
  if (state.x === null) return showErr('Choisissez une position via « Choisir sur la carte » (GPS non disponible dans cette démo).');
  try {
    const j = await api('/api/reports', 'POST', { text, category: $('pCat').value, x: state.x, y: state.y, photoMediaId: state.mediaId });
    $('pTrackId').textContent = j.id;
    $('pConfirm').hidden = false;
    $('pText').value = ''; $('pCount').textContent = '0';
    $('pRemove').onclick();
    loadRecent(3); drawMap();
  } catch (e) { showErr(e.message); }
};
$('pTrackGo').onclick = () => {
  document.querySelector('.nav-links a[data-nav="suivi"]').click();
  $('tId').value = $('pTrackId').textContent;
  $('tGo').click();
};

// --- Carte publique (données réelles, grille fictive) ---
const sevColor = (s) => s === 5 ? '#b3261e' : s === 4 ? '#f97316' : s === 3 ? '#eab308' : (s === 1 || s === 2) ? '#22c55e' : '#94a3b8';
async function drawMap() {
  const j = await api('/api/public/incidents');
  const svg = $('pMap');
  const OX = 40, OY = 10, S = 100;
  const X = (x) => OX + x * S, Y = (y) => OY + (5 - y) * S;
  let h = '';
  for (let i = 0; i <= 5; i++) {
    h += `<line x1="${X(i)}" y1="${OY}" x2="${X(i)}" y2="${OY + 500}" stroke="#e2e8f0"/>`;
    h += `<line x1="${OX}" y1="${Y(i)}" x2="${OX + 500}" y2="${Y(i)}" stroke="#e2e8f0"/>`;
    h += `<text x="${X(i) - 4}" y="${OY + 518}" font-size="11" fill="#64748b">${i}</text>`;
    h += `<text x="${OX - 24}" y="${Y(i) + 4}" font-size="11" fill="#64748b">${i}</text>`;
  }
  j.incidents.forEach((inc) => {
    const c = sevColor(inc.severity);
    h += `<circle cx="${X(inc.x)}" cy="${Y(inc.y)}" r="10" fill="${c}"><title>${esc(inc.id)} — ${esc(inc.domain)} — ${inc.reportCount} signalement(s)${inc.severity === null ? ' — gravité à vérifier' : ' — S' + inc.severity}</title></circle>`;
    h += `<text x="${X(inc.x) + 13}" y="${Y(inc.y) + 4}" font-size="12" font-weight="bold" fill="${c}">${esc(inc.id)}</text>`;
  });
  if (state.x !== null) {
    h += `<circle cx="${X(state.x)}" cy="${Y(state.y)}" r="8" fill="#0b5fff" stroke="#fff" stroke-width="3"><title>Votre point choisi (grille fictive)</title></circle>`;
  }
  svg.innerHTML = h;
}

// --- Signalements récents (données réelles) ---
function fmtDate(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  return 'reçu le ' + d.toLocaleDateString('fr-FR') + ' à ' + d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
}
function thumb(r) {
  if (isMediaId(r.photo)) return `<img src="/api/photos/${esc(r.photo)}" alt="">`;
  return '<span class="noimg">📝</span>';
}
function shortText(t) { const s = String(t || ''); return s.length > 60 ? s.slice(0, 57) + '…' : s; }
async function loadRecent(n) {
  const j = await api('/api/public/reports?limit=' + n);
  $('pRecent').innerHTML = j.reports.map((r) =>
    `<li>${thumb(r)}<div><b>${esc(shortText(r.text) || r.id)}</b><small>${esc(r.category)} · ${fmtDate(r.receivedAt) || 'scénario fictif (sans heure de réception)'} · <i>donnée fictive</i></small></div><span class="pill st-${esc(r.status)}">${esc(r.statusLabel)}</span></li>`
  ).join('') || '<li class="muted">Aucun signalement pour le moment.</li>';
}

// --- Suivi ---
$('tGo').onclick = async () => {
  $('tErr').hidden = true; $('tOut').innerHTML = '';
  const id = $('tId').value.trim();
  if (!id) { $('tErr').textContent = 'Saisissez un identifiant.'; $('tErr').hidden = false; return; }
  try {
    const j = await api('/api/public/reports/' + encodeURIComponent(id));
    const r = j.report;
    let h = `<div class="track"><p><b>${esc(r.id)}</b> <span class="pill st-${esc(r.status)}">${esc(r.statusLabel)}</span></p>`;
    h += `<p>${esc(r.text)}</p><p class="muted">${esc(r.category)} · position fictive (${r.x.toFixed(1)}, ${r.y.toFixed(1)}) km${r.receivedAt ? ' · ' + esc(fmtDate(r.receivedAt)) : ''}</p>`;
    if (isMediaId(r.photo)) h += `<p><a href="/api/photos/${esc(r.photo)}" target="_blank" rel="noopener"><img class="upload preview" style="max-width:220px" src="/api/photos/${esc(r.photo)}" alt="photo du signalement"></a></p>`;
    if (j.incident) h += `<p>Incident associé : <b>${esc(j.incident.id)}</b> (${esc(j.incident.domain)}, ${j.incident.reportCount} signalement(s)).</p>`;
    else h += `<p class="muted">Pas encore rattaché à un incident (regroupement municipal en attente).</p>`;
    h += `<p class="muted">Démonstration : données fictives, aucun délai d'intervention promis.</p></div>`;
    $('tOut').innerHTML = h;
  } catch (e) { $('tErr').textContent = e.message; $('tErr').hidden = false; }
};

(async () => { try { await drawMap(); await loadRecent(3); } catch (e) { console.error(e); } })();
