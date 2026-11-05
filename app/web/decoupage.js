// Multi-problem splitting page: real data only.
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
let ctrl = null;
function newCtrl() { if (ctrl) ctrl.abort(); ctrl = new AbortController(); return ctrl.signal; }

async function api(path, method = 'GET', body = null) {
  const r = await fetch(path, {
    method, headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : null,
    signal: ctrl ? ctrl.signal : undefined,
  });
  const j = await r.json().catch(() => ({}));
  if (r.status === 401) { showLogin(); throw new Error('auth'); }
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
function panelError(id, e) {
  if (String(e && e.message).includes('auth') || (e && e.name === 'AbortError')) return;
  $(id).innerHTML += `<p class="perr">Load failed: ${esc(e.message || e)}</p>`;
}
const famLabel = { 'voirie-nid': 'Roads', 'eclairage': 'Public lighting', 'eau': 'Drainage', 'electricite': 'Electricity', 'assainissement': 'Sanitation', 'dechets': 'Cleanliness', 'inconnu': 'Unknown' };
const famIcon = { 'voirie-nid': '🛣', 'eclairage': '💡', 'eau': '💧', 'electricite': '⚡', 'assainissement': '🚰', 'dechets': '🗑', 'inconnu': '❓' };

let currentReportId = null;

async function loadOverview() {
  const j = await api('/api/municipal/split/overview');
  $('methodNote').textContent = `Method actually used: ${j.method} — ${j.groups} groups, ${j.units} units, ${j.incidents} incidents. ${j.multiProblemReports.length} multi-problem report(s) kept.`;
  const sel = $('repSel');
  sel.innerHTML = j.multiProblemReports.map((id) => `<option value="${esc(id)}">${esc(id)}</option>`).join('')
    || '<option value="">(no multi-problem report in the current state)</option>';
  try { $('gMethod').value = j.method; } catch (e) { /* unknown method: leave CLASSIC */ }
  if (!currentReportId && j.multiProblemReports.length) currentReportId = j.multiProblemReports[0];
  if (currentReportId && j.multiProblemReports.includes(currentReportId)) sel.value = currentReportId;
  else if (j.multiProblemReports.length) { currentReportId = j.multiProblemReports[0]; sel.value = currentReportId; }
  else currentReportId = null;
  if (currentReportId) await loadExample(currentReportId);
  else {
    $('originCard').innerHTML = '<h3>Original report</h3><p class="empty">No multi-problem report in the current state. Load a DEV scenario containing two problems (e.g. jouet-1 + injection).</p>';
    $('subCol').innerHTML = ''; $('incCol').innerHTML = '';
  }
  // Reconstructed incidents table
  const rows = j.perIncident.map((p, i) =>
    `<tr><td>${i + 1}</td><td><b>${esc('Incident ' + p.incidentId)}</b><br><span class="muted">${esc(p.domain)}</span></td><td>${esc(p.domain)}</td><td>${p.units}</td><td>(${p.x.toFixed(1)}, ${p.y.toFixed(1)}) — fictitious grid</td><td><span class="pill st-${esc(p.status)}">${esc(p.status)}</span></td><td><a class="link" href="/municipal/signalements/${esc(p.origins[0] || '')}">See the source →</a></td></tr>`
  ).join('');
  $('incTable').querySelector('tbody').innerHTML = rows || '<tr><td colspan="7" class="empty">No incidents.</td></tr>';
  $('incCountLine').textContent = `${j.incidents} incidents generated from the current state (fictitious data).`;
  // Method
  $('methodCard').innerHTML = `<h2>Grouping method</h2>
    <p><b>Method</b>: ${esc(j.method)}</p>
    <p><b>Groups</b>: ${j.groups} · <b>Units</b>: ${j.units} · <b>Incidents</b>: ${j.incidents}</p>
    <p><b>Secondary problems kept</b>: ${j.multiProblemReports.length ? j.multiProblemReports.map(esc).join(', ') : 'none'}</p>
    <p><b>Uncertainties</b>:</p><ul>${j.uncertaintyReasons.map((u) => `<li>${esc(u)}</li>`).join('') || '<li class="muted">none reported</li>'}</ul>
    <p><b>Justifications</b>:</p><ul>${j.justifications.map((x) => `<li>${esc(x)}</li>`).join('') || '<li class="muted">none</li>'}</ul>
    <p class="muted">${esc(j.note)}</p>`;
}

async function loadExample(reportId) {
  const j = await api('/api/municipal/split/report?reportId=' + encodeURIComponent(reportId));
  const isMedia = /^[0-9a-f]{24}$/.test(j.photo || '');
  $('originCard').innerHTML = `<h3>Original report</h3>
    <p><b>No. ${esc(j.reportId)}</b> <span class="muted">· ${esc(j.category)} · ${esc(j.source)}</span></p>
    <p>« ${esc(j.text)} »</p>
    ${isMedia ? `<a href="/api/photos/${esc(j.photo)}" target="_blank" rel="noopener"><img src="/api/photos/${esc(j.photo)}" alt="report photo" style="max-width:100%;border-radius:10px"></a><p class="muted">1 media item</p><button class="btn ghost" id="originVision">Analyse the photo (AI)</button> <span class="muted" id="originVisionMsg"></span>` : '<p class="muted">No photo.</p>'}
    <p><a class="link" href="/municipal/signalements/${esc(j.reportId)}">Full details →</a></p>`;
  if (isMedia) $('originVision').onclick = () => analyzePhoto(j.reportId, 'originVision', 'originVisionMsg');
  $('subCol').innerHTML = j.subunits.map((u, i) =>
    `<div class="card sub"><h3>${famIcon[u.family] || '❓'} Sub-report ${i + 1}</h3>
    <p><b>${esc(famLabel[u.family] || u.family)}</b><br><span class="muted">${esc(u.id)}</span></p>
    <p><span class="pill st-a-verifier">to verify</span> <span class="pill st-a-verifier">unknown severity</span></p>
    <p class="muted">Source: original text. Status: to verify before grouping.</p></div>`).join('');
  $('incCol').innerHTML = j.linkedIncidents.map((inc) =>
    `<div class="card sub"><h3>Incident (grouping)</h3>
    <p><b>Incident ${esc(inc.id)}</b> <span class="tag calc">GROUPED</span></p>
    <p class="muted">${esc(inc.domain)} · severity ${inc.severity === null ? 'unknown' : 'S' + inc.severity}</p>
    ${j.uncertaintyReasons.map((u) => `<p class="muted">⚠ ${esc(u)}</p>`).join('')}
    <p><a class="link" href="/municipal/dashboard#panelIncidents">See in incidents →</a></p></div>`).join('')
    || '<div class="card sub"><p class="empty">No linked incident yet (grouping pending).</p></div>';
}

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
async function analyzePhoto(reportId, btnId, msgId) {
  const btn = $(btnId), msg = $(msgId);
  btn.disabled = true;
  msg.textContent = 'Visual analysis in progress (real call)…';
  try {
    const j = await api('/api/meta/analyze-image', 'POST', { reportId });
    msg.innerHTML = `Analysis saved (model ${esc(j.model || '?')}, "to verify"). <a class="link" href="/municipal/signalements/${esc(reportId)}">See details →</a>`;
  } catch (e) {
    if (!String(e && e.message).includes('auth')) msg.innerHTML = `<span class="perr">Analysis failed: ${esc(e.message || e)}</span>`;
  } finally { btn.disabled = false; }
}
async function loadMeta() {
  try {
    const j = await api('/api/meta');
    $('metaState').textContent = `Meta status: ${j.state} — model: ${j.model || 'none'} — ${j.message || ''}`;
  } catch (e) {
    if (String(e && e.message).includes('auth') || (e && e.name === 'AbortError')) return;
    $('metaState').textContent = 'Meta status: unavailable (' + (e.message || e) + ')';
  }
}
$('metaVerifyBtn').onclick = async () => {
  const btn = $('metaVerifyBtn');
  btn.disabled = true;
  $('metaState').textContent = 'Meta status: verification in progress (real GET /models call)…';
  try {
    const j = await api('/api/meta/verify', 'POST', {});
    $('metaState').textContent = `Meta status: ${j.meta.state} — model: ${j.meta.model || 'none'} — ${j.meta.message || ''} (call ${j.call.id}, ${j.call.latencyMs} ms)`;
  } catch (e) {
    if (!String(e && e.message).includes('auth')) $('metaState').textContent = 'Meta status: verification failed (' + (e.message || e) + ')';
  } finally { btn.disabled = false; }
};
$('repSel').onchange = () => { currentReportId = $('repSel').value || null; if (currentReportId) loadExample(currentReportId).catch((e) => panelError('originCard', e)); };
$('gRun').onclick = async () => {
  try {
    const j = await api('/api/group', 'POST', { method: $('gMethod').value });
    $('methodNote').textContent = `Grouping ${j.method} run: ${j.groups.length} groups, ${j.incidents} incidents. Previous plan invalidated (replan).`;
    await loadOverview();
  } catch (e) { $('methodNote').innerHTML = `<span class="perr">${esc(e.message || e)}</span>`; }
};
function panelError(id, e) {
  if (String(e && e.message).includes('auth') || (e && e.name === 'AbortError')) return;
  $(id).innerHTML += `<p class="perr">Load failed: ${esc(e.message || e)}</p>`;
}

(async () => {
  try {
    const r = await fetch('/api/municipal/status');
    const j = await r.json();
    if (j.enforced && !j.authenticated) {
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
  } catch (e) { /* panels will show their errors */ }
  newCtrl();
  try { await loadOverview(); } catch (e) { panelError('originCard', e); }
  loadMeta().catch(() => {});
})();
