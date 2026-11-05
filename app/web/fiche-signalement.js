// Report details: real read, authorised and logged edits.
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
let ctrl = null;
function newCtrl() { if (ctrl) ctrl.abort(); ctrl = new AbortController(); return ctrl.signal; }
const reportId = decodeURIComponent(location.pathname.split('/').pop() || '');

async function api(path, method = 'GET', body = null) {
  const r = await fetch(path, {
    method, headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : null,
    signal: ctrl ? ctrl.signal : undefined,
  });
  const j = await r.json().catch(() => ({}));
  if (r.status === 401) { showLogin(); throw new Error('auth'); }
  if (r.status === 404) throw new Error('Report not found.');
  if (!r.ok) throw new Error(j.error || ('HTTP ' + r.status));
  return j;
}
function showLogin() {
  $('loginOverlay').hidden = false;
  $('loginGo').onclick = async () => {
    const r = await fetch('/api/municipal/login', { method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: $('loginToken').value }) });
    if (r.ok) location.reload();
    else $('loginErr').textContent = 'Invalid token.';
  };
}
function needAuth(fn) { return async (...a) => { try { await fn(...a); } catch (e) { if (!String(e && e.message).includes('auth')) throw e; } }; }

let current = null;

function statusPill(r) {
  if (r.verificationNote) return `<span class="pill st-valide-humain">Verified (human)</span>`;
  return `<span class="pill st-propose">To verify</span>`;
}

function render(j) {
  const r = j.report;
  current = r;
  $('crumb').innerHTML = `Reports › ${esc(r.id)}`;
  const isMedia = /^[0-9a-f]{24}$/.test(r.photo || '');
  const photo = isMedia
    ? `<a href="/api/photos/${esc(r.photo)}" target="_blank" rel="noopener"><img src="/api/photos/${esc(r.photo)}" alt="report photo" style="max-width:100%;border-radius:10px"></a>
       <p class="muted">${j.photoMeta ? `${esc(j.photoMeta.mime || '')} · ${j.photoMeta.size} bytes · received on ${esc(new Date(j.photoMeta.createdAt).toLocaleString('en-US'))}` : 'uploaded media'}</p>`
    : '<p class="empty">No photo — empty state (no image fabricated).</p>';
  const fams = (j.subunits || []).map((u) => u.family);
  const uniqFams = [...new Set(fams)];
  const famLabel = { 'voirie-nid': 'Roads', 'eclairage': 'Public lighting', 'eau': 'Drainage', 'electricite': 'Electricity', 'assainissement': 'Sanitation', 'dechets': 'Cleanliness', 'inconnu': 'Unknown' };
  const unknown = [];
  if (r.severityHint === null || r.severityHint === undefined) unknown.push('severity');
  if (r.exposureHint === null || r.exposureHint === undefined) unknown.push('exposure');
  if (!r.gpsLat) unknown.push('exact GPS position');
  const when = r.receivedAt ? new Date(r.receivedAt).toLocaleString('en-US') : 'DEV scenario (no receipt time)';
  $('ficheBody').innerHTML = `
  <section class="card"><div class="btn-row">
    <button class="btn ghost" id="backBtn">← Back to reports</button>
    <span class="pill st-info" style="background:#e0f2fe;color:#075985;border-radius:14px;padding:3px 10px;font-size:11.5px;font-weight:700">A report can contain several problems: ${uniqFams.length} detected here (${uniqFams.map((f) => esc(famLabel[f] || f)).join(' + ') || 'none'}).</span>
    <span style="flex:1"></span>
    <button class="btn ghost" id="editBtn">✏ Edit</button>
    <button class="btn primary" id="verifyBtn">✓ Update status</button>
  </div></section>
  <section class="row2">
    <div>
      <div class="card"><h2>Photo ${isMedia ? '(1 photo)' : ''}</h2>${photo}${isMedia ? '<div class="btn-row"><button class="btn primary" id="visionBtn">Analyse the photo (AI)</button></div><p class="muted" id="visionMsg"></p>' : ''}</div>
      <div class="card"><h2>Description</h2><p>« ${esc(r.text)} »</p>
      <p class="muted">Exact original text — no AI rephrasing replaces it.</p></div>
      <div class="card"><h2>Associated problems (${(j.subunits || []).length})</h2>
      ${((j.subunits || []).map((u) => `<span class="chip">${esc(famLabel[u.family] || u.family)}</span> <span class="muted">${esc(u.id)}</span>`).join(' ') || '<p class="empty">none</p>')}
      <p class="muted">Origin kept (ORIGIN:FAMILY); a secondary problem never disappears when another is handled.</p></div>
      ${j.extraction ? `<div class="card"><h2>AI extraction (to verify)</h2><pre class="dump">${esc(JSON.stringify(j.extraction, null, 1))}</pre></div>` : ''}
      ${j.visualAnalysis ? `<div class="card"><h2>AI visual analysis (to verify)</h2><pre class="dump">${esc(JSON.stringify(j.visualAnalysis.analysis || j.visualAnalysis, null, 1))}</pre></div>` : ''}
    </div>
    <div>
      <div class="card"><h2>General information</h2>
        <p><b>Report No.</b>: ${esc(r.id)} <button class="link" id="copyId">copy</button></p>
        <p><b>Source</b>: ${esc(r.source)} ${r.source === 'manuel' ? '(citizen / manual)' : '(DEV scenario)'}</p>
        <p><b>Date</b>: ${esc(when)}</p>
        <p><b>Verification status</b>: ${statusPill(r)}</p>
        ${r.verificationNote ? `<p class="muted">Note : ${esc(r.verificationNote)}${r.verifiedAt ? ' (' + esc(new Date(r.verifiedAt).toLocaleString('en-US')) + ')' : ''}</p>` : ''}
      </div>
      <div class="card"><h2>Location</h2>
        <p>Fictitious position: <b>(${Number(r.x).toFixed(1)}, ${Number(r.y).toFixed(1)}) km</b> — 5×5 grid, not a real address.</p>
        ${r.gpsLat ? `<p>Browser GPS reading: ${Number(r.gpsLat).toFixed(5)}, ${Number(r.gpsLon).toFixed(5)}${r.gpsAccuracy != null ? ` (±${Math.round(r.gpsAccuracy)} m)` : ''} — provided by the reporter.</p>` : '<p class="muted">No GPS position (manual entry on the grid).</p>'}
        <p class="muted">Address / district / municipality: unavailable (no address reported, no geocoding).</p>
      </div>
      <div class="card"><h2>Severity and exposure</h2>
        <p>Reported severity: <b>${r.severityHint === null || r.severityHint === undefined ? 'Unknown' : 'S' + r.severityHint}</b></p>
        <p>Reported exposure: <b>${r.exposureHint === null || r.exposureHint === undefined ? 'Unknown' : 'E' + r.exposureHint}</b></p>
        <p class="muted">Never inferred from the category; conflicting values kept, never averaged.</p>
      </div>
      <div class="card"><h2>Unknown information kept</h2>
        <p>${unknown.length ? 'Undetermined fields: <b>' + unknown.map(esc).join(', ') + '</b>. ' : 'No unknown fields. '}Human verification is required before any operational assignment.</p>
      </div>
    </div>
  </section>
  <section class="row2">
    <div class="card"><h2>Associated incidents (${j.linkedIncidents.length})</h2>
      ${j.linkedIncidents.map((i) => `<p><b>${esc(i.id)}</b> — ${esc(i.domain)} — severity ${i.severity === null ? 'unknown' : 'S' + i.severity} <a class="link" href="/municipal/decoupage">see the splitting →</a></p>`).join('') || '<p class="empty">No linked incident (grouping pending).</p>'}
    </div>
    <div class="card"><h2>History</h2>
      <ul class="timeline">${(j.history || []).map((e) => {
        const d = e.at ? new Date(e.at) : null;
        return `<li><span class="tico">•</span><div><b>${esc(e.label)}</b><br><span class="muted">${esc(e.detail || '')}</span></div><time>${esc(d ? d.toLocaleString('en-US') : '?')}</time></li>`;
      }).join('') || '<li class="empty">No related events.</li>'}</ul>
      <p class="muted">Fictitious data — timestamped municipal log.</p>
    </div>
  </section>`;
  $('backBtn').onclick = () => { location.href = '/municipal/dashboard#panelReports'; };
  $('copyId').onclick = () => { try { navigator.clipboard.writeText(r.id); } catch (e) {} };
  $('editBtn').onclick = openEdit;
  $('verifyBtn').onclick = openVerify;
  const vb = $('visionBtn');
  if (vb) vb.onclick = runVision;
}

async function runVision() {
  const btn = $('visionBtn'), msg = $('visionMsg');
  btn.disabled = true;
  msg.textContent = 'Visual analysis in progress (real call)…';
  try {
    const j = await api('/api/meta/analyze-image', 'POST', { reportId: current.id });
    msg.textContent = `Analysis saved (model ${j.model || '?'}). Reloading…`;
    await load();
  } catch (e) {
    if (String(e && e.message).includes('auth')) return;
    msg.innerHTML = `<span class="perr">Analysis failed: ${esc(e.message || e)}</span>`;
    btn.disabled = false;
  }
}
function fillEdit() {
  const r = current;
  $('editId').textContent = r.id;
  $('eText').value = r.text || '';
  $('eCat').value = r.category || 'autre';
  $('eSev').value = (r.severityHint === null || r.severityHint === undefined) ? '' : String(r.severityHint);
  $('eExp').value = (r.exposureHint === null || r.exposureHint === undefined) ? '' : String(r.exposureHint);
  $('editErr').textContent = '';
}
function openEdit() { fillEdit(); $('editModal').hidden = false; }
function openVerify() {
  $('vNote').value = (current && current.verificationNote) || '';
  $('verifyErr').textContent = '';
  $('verifyModal').hidden = false;
}
async function saveEdit() {
  const body = {
    text: $('eText').value,
    category: $('eCat').value,
    severityHint: $('eSev').value === '' ? null : +$('eSev').value,
    exposureHint: $('eExp').value === '' ? null : +$('eExp').value,
  };
  try {
    const j = await api('/api/municipal/report/' + encodeURIComponent(current.id), 'PATCH', body);
    $('editModal').hidden = true;
    await load();
    if (j.staleGrouping) {
      const note = document.createElement('p');
      note.className = 'muted';
      note.innerHTML = 'Saved. Grouping not re-run: <a class="link" href="/municipal/decoupage">re-group from the Splitting page</a> to propagate.';
      const fb = $('ficheBody');
      fb.insertBefore(note, fb.firstChild);
    }
  } catch (e) { $('editErr').textContent = e.message || String(e); }
}
async function saveVerify() {
  const v = $('vNote').value.trim();
  try {
    await api('/api/municipal/report/' + encodeURIComponent(current.id), 'PATCH', { verificationNote: v === '' ? null : v });
    $('verifyModal').hidden = true;
    await load();
  } catch (e) { $('verifyErr').textContent = e.message || String(e); }
}
$('editSave').onclick = () => saveEdit();
$('editCancel').onclick = () => { $('editModal').hidden = true; };
$('verifySave').onclick = () => saveVerify();
$('verifyCancel').onclick = () => { $('verifyModal').hidden = true; };

// Search + alerts + help: same endpoints as the dashboard.
async function loadSearch(q) {
  const box = $('qResults');
  if (!q || q.trim().length < 2) { box.hidden = true; return; }
  try {
    const j = await api('/api/municipal/dashboard/search?q=' + encodeURIComponent(q.trim()) + '&limit=8');
    box.innerHTML = j.results.map((r) =>
      `<div data-kind="${esc(r.kind)}" data-id="${esc(r.id)}"><b>${esc(r.id)}</b> <span class="muted">[${esc(r.kind)}]</span><br><span class="muted">${esc(String(r.text || '').slice(0, 70))}</span></div>`).join('')
      || '<div class="muted">No results.</div>';
    box.hidden = false;
    box.querySelectorAll('div[data-id]').forEach((d) => {
      d.onclick = () => {
        if (d.dataset.kind === 'report') location.href = '/municipal/signalements/' + encodeURIComponent(d.dataset.id);
        else location.href = '/municipal/dashboard#panelIncidents';
      };
    });
  } catch (e) { box.hidden = true; }
}
let qTimer = null;
$('q').oninput = () => { clearTimeout(qTimer); qTimer = setTimeout(() => loadSearch($('q').value), 300); };
document.addEventListener('click', (e) => { if (!e.target.closest('.search-wrap')) $('qResults').hidden = true; });
$('bellBtn').onclick = async () => {
  const box = $('alerts');
  try {
    const j = await api('/api/municipal/dashboard/incident-status');
    const s5 = (j.buckets.find((b) => b.status === 'escalade-s5') || {}).count || 0;
    box.innerHTML = s5 > 0
      ? `<div class="alert">⚠ ${s5} S5 incident(s) in human escalation — never dispatched automatically.</div>`
      : '<div class="alert" style="background:#f0fdf4;border-color:#bbf7d0;color:#15803d">No S5 escalation in progress.</div>';
    box.hidden = false;
    setTimeout(() => { box.hidden = true; }, 6000);
  } catch (e) { /* silent */ }
};
$('helpBtn').onclick = () => { $('helpModal').hidden = false; };
$('helpClose').onclick = () => { $('helpModal').hidden = true; };
$('burger').onclick = () => { $('sidebar').classList.toggle('open'); };

async function load() {
  newCtrl();
  const j = await api('/api/municipal/report/' + encodeURIComponent(reportId));
  render(j);
}

(async () => {
  try {
    const r = await fetch('/api/municipal/status');
    const s = await r.json();
    if (s.enforced && !s.authenticated) {
      const ov = $('loginOverlay'); ov.hidden = false;
      $('loginGo').onclick = async () => {
        const r2 = await fetch('/api/municipal/login', { method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ token: $('loginToken').value }) });
        if (r2.ok) location.reload();
        else $('loginErr').textContent = 'Invalid token.';
      };
      return;
    }
  } catch (e) { /* the details page will show the error */ }
  try { await load(); } catch (e) {
    if (!String(e && e.message).includes('auth')) $('ficheBody').innerHTML = `<div class="card"><p class="perr">${esc(e.message || e)}</p><p><a class="link" href="/municipal/dashboard">← Back to the dashboard</a></p></div>`;
  }
})();
