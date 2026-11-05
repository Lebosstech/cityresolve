// CityResolve municipal dashboard: real data only.
// Each panel loads independently (skeleton, error, empty);
// in-flight requests are cancelled when the period changes.
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
let ctrl = null;
function newCtrl() { if (ctrl) ctrl.abort(); ctrl = new AbortController(); return ctrl.signal; }

async function api(path, method = 'GET', body = null) {
  const r = await fetch(path, {
    method,
    headers: { 'Content-Type': 'application/json' },
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

function periodQuery() {
  const p = $('period').value;
  if (p === 'custom') {
    const f = $('fromDate').value, t = $('toDate').value;
    if (!f || !t) return null;
    return `period=custom&from=${encodeURIComponent(f + 'T00:00:00Z')}&to=${encodeURIComponent(t + 'T23:59:59Z')}`;
  }
  return `period=${encodeURIComponent(p)}`;
}

function panelError(id, e) {
  if (String(e && e.message).includes('auth')) return;
  if (e && e.name === 'AbortError') return;
  $(id).innerHTML += `<p class="perr">Load failed: ${esc(e.message || e)}</p>`;
}

async function loadSummary() {
  const q = periodQuery();
  if (!q) return;
  const j = await api('/api/municipal/dashboard/summary?' + q);
  const evo = (kpi) => (kpi.deltaPct === null || kpi.deltaPct === undefined)
    ? '<span class="ksub">insufficient reference</span>'
    : `<span class="kevo ${kpi.deltaPct >= 0 ? 'up' : 'down'}">${kpi.deltaPct >= 0 ? '↑' : '↓'} ${Math.abs(kpi.deltaPct).toFixed(0)} %</span>`;
  $('kpiReports').innerHTML = `<span class="kico">💬</span><div><b>${j.reports.count}</b><span class="klab">reports</span></div>${evo(j.reports)}`;
  $('kpiIncidents').innerHTML = `<span class="kico">⚠</span><div><b>${j.incidents.count}</b><span class="klab">incidents</span><span class="ksub">current reconstruction</span></div>`;
  $('kpiTeams').innerHTML = `<span class="kico">👥</span><div><b>${j.teams.available}</b><span class="klab">teams available</span><span class="ksub">of ${j.teams.total} (simulated)</span></div>`;
  const b = j.budget;
  $('kpiBudget').innerHTML = `<span class="kico">💰</span><div style="flex:1"><b>${b.total}</b><span class="klab">Budget (${esc(b.unit)})</span><div class="budget-bar"><i style="width:${Math.min(100, b.pctUsed).toFixed(1)}%"></i></div><span class="ksub">committed ${b.committed.toFixed(1)} · remaining ${(b.remaining).toFixed(1)} · ${b.pctUsed.toFixed(0)}% used (${esc(b.source)})</span></div>`;
}

async function loadLatest() {
  const j = await api('/api/municipal/dashboard/latest-report');
  const box = $('panelLatest');
  const r = j.report;
  if (!r) { box.innerHTML = '<h2>⚡ Latest report received</h2><p class="empty">No reports yet.</p>'; return; }
  const hasPhoto = /^[0-9a-f]{24}$/.test(r.photo || '');
  const img = hasPhoto
    ? `<a href="/api/photos/${esc(r.photo)}" target="_blank" rel="noopener"><img src="/api/photos/${esc(r.photo)}" alt="report photo"></a>`
    : '<span class="noimg">📝</span>';
  const fams = (r.families || []).map((f) => `<span class="chip">${esc(f)}</span>`).join('');
  const when = r.receivedAt ? new Date(r.receivedAt).toLocaleString('en-US') : 'fictitious scenario (no receipt time)';
  box.innerHTML = `<h2>⚡ Latest report received</h2>
    <div class="latest">${img}<div><h3>${esc(r.id)} — ${esc(r.category)}</h3>
    <p>${esc(r.text)}</p><p>${fams}</p>
    <p class="muted">${esc(when)} · status: <b>${esc(r.statusLabel)}</b> · <i>fictitious data</i></p>
    <a class="link" href="#panelReports">See the report →</a>${hasPhoto ? ' <button class="btn ghost" id="latestVision">Analyse the photo (AI)</button> <span class="muted" id="latestVisionMsg"></span>' : ''}</div></div>`;
  if (hasPhoto) $('latestVision').onclick = () => analyzePhoto(r.id, 'latestVision', 'latestVisionMsg');
}

const donutColors = { 'planifie': '#14b8a6', 'en-attente': '#f97316', 'en-cours': '#5eead4', 'resolus': '#94a3b8', 'escalade-s5': '#b3261e', 'non-affecte': '#f97316', 'a-analyser': '#eab308' };
const donutLabels = { 'planifie': 'Planned', 'non-affecte': 'Pending', 'a-analyser': 'To review', 'escalade-s5': 'S5 escalations' };
async function loadStatus() {
  const j = await api('/api/municipal/dashboard/incident-status');
  const box = $('panelStatus');
  if (!j.total) { box.innerHTML = '<h2>📊 Incident status</h2><p class="empty">No incidents.</p>'; return; }
  const R = 54, C = 2 * Math.PI * R;
  let acc = 0, segs = '';
  j.buckets.forEach((b) => {
    const frac = b.count / j.total;
    segs += `<circle cx="70" cy="70" r="${R}" fill="none" stroke="${donutColors[b.status] || '#94a3b8'}" stroke-width="20" stroke-dasharray="${(frac * C).toFixed(1)} ${C.toFixed(1)}" stroke-dashoffset="${(-acc * C).toFixed(1)}" transform="rotate(-90 70 70)"><title>${esc(b.status)} : ${b.count}</title></circle>`;
    acc += frac;
  });
  const lis = j.buckets.map((b) =>
    `<li><i style="background:${donutColors[b.status] || '#94a3b8'}"></i>${esc(donutLabels[b.status] || b.status)}<b>${b.count} (${b.pct.toFixed(0)} %)</b></li>`).join('');
  box.innerHTML = `<h2>📊 Incident status</h2><div class="donut-wrap">
    <svg width="140" height="140" viewBox="0 0 140 140" role="img" aria-label="Status distribution">${segs}<text x="70" y="66" text-anchor="middle" font-size="26" font-weight="800">${j.total}</text><text x="70" y="86" text-anchor="middle" font-size="12" fill="#64748b">incidents</text></svg>
    <ul class="donut-legend">${lis}</ul></div>
    <p class="muted">Exclusive statuses derived from the real state (sum = total).</p>`;
}

const ANCHOR = { lat: 5.32, lon: -4.02 };
const KM = 111.32;
const gridToLatLng = (x, y) => [ANCHOR.lat + (y - 2.5) / KM, ANCHOR.lon + (x - 2.5) / (KM * Math.cos(ANCHOR.lat * Math.PI / 180))];
const sevColor = (s) => s === 5 ? '#b3261e' : s === 4 ? '#f97316' : s === 3 ? '#eab308' : (s === 1 || s === 2) ? '#22c55e' : '#94a3b8';
let dashMap = null, dashLayer = null;
async function loadMap() {
  const j = await api('/api/municipal/dashboard/map?minx=0&miny=0&maxx=5&maxy=5&limit=500');
  if (typeof L === 'undefined') { $('dashMap').innerHTML = '<p class="empty">Map background unavailable (connection required).</p>'; return; }
  if (!dashMap) {
    dashMap = L.map('dashMap').setView([ANCHOR.lat, ANCHOR.lon], 13);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors' }).addTo(dashMap);
    dashLayer = L.layerGroup().addTo(dashMap);
  }
  dashLayer.clearLayers();
  j.incidents.forEach((inc) => {
    const [lat, lon] = gridToLatLng(inc.x, inc.y);
    L.circleMarker([lat, lon], { radius: 9, color: sevColor(inc.severity), fillColor: sevColor(inc.severity), fillOpacity: 0.85, weight: 2 })
      .bindPopup(`<b>${esc(inc.id)}</b> (projected fictitious position)<br>${esc(inc.domain)} — ${inc.reportCount} report(s)`)
      .bindTooltip(inc.id, { permanent: false }).addTo(dashLayer);
  });
}

let actCursor = null;
async function loadActivity(append) {
  let url = '/api/municipal/dashboard/activity?limit=8';
  if (append && actCursor !== null && actCursor !== undefined) url += '&cursor=' + actCursor;
  const j = await api(url);
  actCursor = j.nextCursor;
  const icons = { signalement: '💬', regroupement: '⚠', plan: '✓', validation: '📝', simulation: '🧪', injection: '📥', equipe: '👥', ia: '✨', systeme: '⚙' };
  const html = j.items.map((e) => {
    const d = e.at ? new Date(e.at) : null;
    const when = d ? d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : '?';
    return `<li><span class="tico">${icons[e.type] || '•'}</span><div><b>${esc(e.label)}</b><br><span class="muted">${esc(e.detail || '')}</span></div><time>${esc(when)}</time></li>`;
  }).join('');
  $('timeline').innerHTML = append ? ($('timeline').innerHTML + html) : (html || '<li class="empty">No events.</li>');
  $('actNext').hidden = (actCursor === null || actCursor === undefined);
}

async function loadPlan() {
  const j = await api('/api/municipal/dashboard/priority-plan?limit=50');
  const tb = $('planTable').querySelector('tbody');
  if (!j.plan) {
    tb.innerHTML = '<tr><td colspan="7" class="empty">No plan generated — run "Optimize the plan".</td></tr>';
    $('planMeta').textContent = ''; $('planUnassigned').innerHTML = '';
    return;
  }
  const p = j.plan;
  tb.innerHTML = j.rows.map((r) =>
    `<tr><td>${r.rank}</td><td><b>${esc(r.incidentId)}</b><br><span class="muted">${esc(r.label)}</span></td><td>${esc(r.lieu)}</td><td><span class="pill p-${esc(r.priority)}">${esc(r.priorityLabel)}</span></td><td>${esc(r.recommandation)}</td><td>${esc(r.resources)}</td><td><span class="pill st-${esc(r.status)}">${esc(r.status)}</span></td></tr>`
  ).join('');
  $('planMeta').textContent = `${p.planId} (v${p.version}) — Planned Q ${p.q.toFixed(1)} — cost ${p.totalCost.toFixed(1)}/120 — feasible: ${p.feasible ? 'yes' : 'no'}${p.violations.length ? ' — violations: ' + p.violations.join(' ; ') : ''} — validation: ${p.validation || 'pending (human)'}. Provisional Q policy, not frozen.`;
  let un = '';
  if (j.unassigned.length) un += `<p><b>Unassigned:</b></p><ul>${j.unassigned.map((u) => `<li>${esc(u.incidentId)} — ${esc(u.motif)}</li>`).join('')}</ul>`;
  if (p.escalations.length) un += `<p class="perr">S5 in human escalation (never dispatched): ${p.escalations.map(esc).join(', ')}</p>`;
  $('planUnassigned').innerHTML = un;
}

async function loadSearch(q) {
  const box = $('qResults');
  if (!q || q.trim().length < 2) { box.hidden = true; return; }
  try {
    const j = await api('/api/municipal/dashboard/search?q=' + encodeURIComponent(q.trim()) + '&limit=8');
    box.innerHTML = j.results.map((r) =>
      `<div><b>${esc(r.id)}</b> <span class="muted">[${esc(r.kind)}]</span><br><span class="muted">${esc(String(r.text || '').slice(0, 70))}</span></div>`
    ).join('') || '<div class="muted">No results.</div>';
    box.hidden = false;
  } catch (e) { box.hidden = true; }
}

async function loadAlerts() {
  try {
    const j = await api('/api/municipal/dashboard/incident-status');
    const s5 = (j.buckets.find((b) => b.status === 'escalade-s5') || {}).count || 0;
    const badge = $('bellBadge');
    if (s5 > 0) { badge.textContent = s5; badge.hidden = false; }
    else badge.hidden = true;
  } catch (e) { /* silent */ }
}

async function reloadAll() {
  newCtrl();
  const jobs = [
    ['kpiReports', loadSummary], ['panelLatest', loadLatest], ['panelStatus', loadStatus],
    ['panelMap', loadMap], ['panelActivity', () => loadActivity(false)], ['panelPlan', loadPlan],
  ];
  await Promise.allSettled(jobs.map(async ([id, fn]) => {
    try { await fn(); } catch (e) { panelError(id, e); }
  }));
  loadAlerts();
}

$('period').onchange = () => {
  $('customRange').hidden = $('period').value !== 'custom';
  if ($('period').value !== 'custom') reloadAll();
};
$('customGo').onclick = () => reloadAll();
$('actMore').onclick = () => loadActivity(false);
$('actNext').onclick = () => loadActivity(true);
$('optBtn').onclick = async () => {
  $('optBtn').disabled = true;
  try {
    const r = await fetch('/api/plan', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}', signal: ctrl ? ctrl.signal : undefined });
    const j = await r.json().catch(() => ({}));
    if (r.status === 401) { showLogin(); return; }
    if (!r.ok) throw new Error(j.error || ('HTTP ' + r.status));
    await reloadAll();
  } catch (e) { $('planMeta').innerHTML = `<span class="perr">Optimisation failed: ${esc(e.message || e)}</span>`; }
  finally { $('optBtn').disabled = false; }
};
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
document.querySelectorAll('.side-nav a[data-anchor]').forEach((a) => {
  a.onclick = (e) => {
    e.preventDefault();
    document.querySelectorAll('.side-nav a').forEach((x) => x.classList.remove('active'));
    a.classList.add('active');
    const t = document.getElementById(a.dataset.anchor);
    if (t) t.scrollIntoView({ behavior: 'smooth' });
    document.getElementById('sidebar').classList.remove('open');
  };
});

function fmtT(m) { const d = Math.floor(m / 1440), h = String(Math.floor(m % 1440 / 60)).padStart(2, '0'), mm = String(m % 60).padStart(2, '0'); return `D${d} ${h}:${mm}`; }
function sevCellDash(i) {
  if (i.severity === null || i.severity === undefined) return `<span class="pill p-a-verifier">UNKNOWN</span>`;
  return `${i.severity}${i.severity >= 5 ? ' <span class="pill p-critique">S5</span>' : ''}`;
}
async function loadReportsPanel() {
  const j = await api('/api/reports');
  const rows = j.reports.slice(0, 50);
  $('groupMeta').textContent = `${j.reports.length} report(s) in total (DEV scenarios + manual).`;
  const tb = $('repTable').querySelector('tbody');
  tb.innerHTML = rows.map((r) =>
    `<tr><td><a class="link" href="/municipal/signalements/${esc(r.id)}">${esc(r.id)}</a>${j.manual.includes(r.id) ? ' <span class="tag hum">MANUAL</span>' : ''}</td><td>${esc(r.text.slice(0, 80))}</td><td>${esc(r.category)}</td><td>(${r.x.toFixed(1)}, ${r.y.toFixed(1)})</td><td>${r.severityHint ?? '?'} / ${r.exposureHint === null || r.exposureHint === undefined ? '?' : r.exposureHint}</td></tr>`
  ).join('') || '<tr><td colspan="5" class="empty">No reports.</td></tr>';
}
async function loadIncidentsPanel() {
  // Detailed table = full municipal endpoint (bounded by maxReportsTotal).
  // The map uses /map (bbox + limit) so it never loads everything.
  const j = await api('/api/incidents');
  $('incCount').textContent = `(${j.incidents.length})`;
  $('incTable').querySelector('tbody').innerHTML = j.incidents.map((i) =>
    `<tr><td>${esc(i.id)}</td><td>${esc(i.reportIds ? i.reportIds.join(', ') : i.reportCount + ' report(s)')}</td><td>${sevCellDash(i)}</td><td>${i.exposure === null || i.exposure === undefined ? '?' : esc(String(i.exposure))}</td><td>${esc(i.domain)}</td><td>${i.weight !== undefined ? i.weight.toFixed(3) : '—'}</td><td>${i.deadline === -2 ? 'to verify' : i.deadline < 0 ? 'escalation' : fmtT(i.deadline)}</td><td>${i.confidence !== undefined ? i.confidence.toFixed(2) : '—'}</td></tr>`
  ).join('') || '<tr><td colspan="8" class="empty">No incidents.</td></tr>';
}
async function runGroupDash() {
  const j = await api('/api/group', 'POST', { method: $('gMethod').value });
  $('groupMeta').innerHTML = `Grouping ${j.method}: ${j.groups.length} groups, ${j.incidents.length} incidents. F1=${j.metrics.available ? j.metrics.pairwise.f1.toFixed(3) + ' (DEV ground truth)' : 'not computed'}. Previous plan invalidated (replan). <a class="link" href="/municipal/decoupage">Open the Splitting page →</a>`;
  await reloadAll();
}
async function runSimDash() {
  const box = $('simBox');
  try {
    const j = await api('/api/simulate', 'POST', {});
    const r = j.result;
    let h = `<p>Simulated Q: <b>${r.q === null ? 'undefined' : r.q.toFixed(1)}</b> — feasible: ${r.feasible ? 'yes' : '<b>no</b>'} — true cost ${r.totalCost.toFixed(1)}</p>`;
    if (r.violations.length) h += `<p class="perr">Violations: ${r.violations.map(esc).join(' ; ')}</p>`;
    h += '<ul>' + r.outcomes.map((o) => `<li>${esc(o.incidentId)} → ${esc(o.truthId || '?')} : R=${o.result} — ${esc(o.reason)}</li>`).join('') + '</ul>';
    box.innerHTML = h;
  } catch (e) { box.innerHTML = `<p class="perr">${esc(e.message || e)}</p>`; }
}
async function injectDash(kind) {
  const box = $('injBox');
  try {
    const j = kind === 'team'
      ? await api('/api/inject', 'POST', { type: 'team_down', teamId: 'equipe-1' })
      : await api('/api/inject', 'POST', { type: 'reports', reports: [{ text: $('iText').value || 'signalement injecté (dashboard)', category: $('iCat').value, x: +$('iX').value, y: +$('iY').value, t: +$('iT').value }] });
    const n = j.necessity;
    let h = `<p>Necessity <b>${esc(n.code)}</b> — ${n.necessary ? 'review required' : 'stability (no unjustified change)'} — ${esc(n.detail)}</p>`;
    if (j.diff) h += `<p>Change: ${j.diff.material ? '<b>material</b>' : 'cosmetic'} — ${esc(j.diff.detail)}</p>`;
    if (j.plan) h += `<p>New plan: Q=${j.plan.q.toFixed(1)}, cost=${j.plan.totalCost.toFixed(1)}.</p>`;
    box.innerHTML = h + '<p><a class="link" href="/municipal/revision">Open the Review page →</a></p>';
    await reloadAll();
  } catch (e) { box.innerHTML = `<p class="perr">${esc(e.message || e)}</p>`; }
}
async function runCompareDash() {
  const box = $('c2Box');
  try {
    const j = await api('/api/compare-methods');
    let h = `<p>CLASSIC: ${j.classique.groups.length} groups, F1=${j.classique.f1 ? j.classique.f1.f1.toFixed(3) : '—'}, Q=${j.classique.planQ === null ? '—' : j.classique.planQ.toFixed(1)}/${j.classique.simQ === null ? '—' : j.classique.simQ.toFixed(1)}</p>`;
    h += j.metaAvailable
      ? `<p>META : ${j.meta.groups.length} groupes, F1=${j.meta.f1 ? j.meta.f1.f1.toFixed(3) : '—'}, Q=${j.meta.planQ === null ? '—' : j.meta.planQ.toFixed(1)}/${j.meta.simQ === null ? '—' : j.meta.simQ.toFixed(1)}</p>`
      : `<p>META: unavailable (${esc(j.metaState)} — no simulated result).</p>`;
    h += `<p>Pair disagreements: <b>${j.disagreements.length}</b>. ${esc(j.note)}</p><p><a class="link" href="/municipal/planification">Open the Planning page →</a></p>`;
    box.innerHTML = h;
  } catch (e) { box.innerHTML = `<p class="perr">${esc(e.message || e)}</p>`; }
}
let jCursor = null;
async function loadJournalPanel(reset) {
  const tb = $('jTable').querySelector('tbody');
  if (reset) { tb.innerHTML = ''; jCursor = null; }
  let url = '/api/journal?limit=15';
  if (!reset && jCursor !== null && jCursor !== undefined) url += '&cursor=' + jCursor;
  try {
    const j = await api(url);
    tb.innerHTML += j.entries.map((e) =>
      `<tr><td>${e.seq}</td><td>${esc(String(e.at).slice(0, 16).replace('T', ' '))}</td><td>${esc(e.event)}</td><td><pre class="dump">${esc(JSON.stringify(e.details || {}, null, 0)).slice(0, 160)}</pre></td></tr>`
    ).join('');
    $('jCount').textContent = `(${j.entries.length} shown)`;
    jCursor = j.nextCursor === undefined ? null : j.nextCursor;
    $('jMore').hidden = jCursor === null || jCursor === undefined;
  } catch (e) { tb.innerHTML = `<tr><td colspan="4" class="perr">${esc(e.message || e)}</td></tr>`; }
}
async function analyzePhoto(reportId, btnId, msgId) {
  const btn = $(btnId), msg = $(msgId);
  btn.disabled = true;
  msg.textContent = 'Visual analysis in progress (real call)…';
  try {
    const j = await api('/api/meta/analyze-image', 'POST', { reportId });
    msg.innerHTML = `Analysis saved (model ${esc(j.model || '?')}, "to verify"). <a class="link" href="/municipal/signalements/${esc(reportId)}">See details →</a>`;
    loadJournalPanel(true).catch(() => {});
  } catch (e) {
    if (String(e && e.message).includes('auth')) return;
    msg.innerHTML = `<span class="perr">Analysis failed: ${esc(e.message || e)}</span>`;
  } finally { btn.disabled = false; }
}
async function loadMetaBox() {
  try {
    const j = await api('/api/meta');
    $('metaState').textContent = `Meta status: ${j.state} — model: ${j.model || 'none'} — ${j.message || ''}`;
  } catch (e) {
    if (String(e && e.message).includes('auth') || (e && e.name === 'AbortError')) return;
    $('metaState').textContent = 'Meta status: unavailable (' + (e.message || e) + ')';
  }
  try {
    const c = await api('/api/meta/calls');
    $('metaCalls').textContent = `${c.calls.length} Meta call(s) logged — real calls or explicit refusals, no simulated results.`;
  } catch (e) { /* silent */ }
}
$('metaVerifyBtn').onclick = async () => {
  const btn = $('metaVerifyBtn');
  btn.disabled = true;
  $('metaState').textContent = 'Meta status: verification in progress (real GET /models call)…';
  try {
    const j = await api('/api/meta/verify', 'POST', {});
    $('metaState').textContent = `Meta status: ${j.meta.state} — model: ${j.meta.model || 'none'} — ${j.meta.message || ''} (call ${j.call.id}, ${j.call.latencyMs} ms)`;
    const c = await api('/api/meta/calls');
    $('metaCalls').textContent = `${c.calls.length} Meta call(s) logged — real calls or explicit refusals, no simulated results.`;
    loadJournalPanel(true).catch(() => {});
  } catch (e) {
    if (!String(e && e.message).includes('auth')) $('metaState').textContent = 'Meta status: verification failed (' + (e.message || e) + ')';
  } finally { btn.disabled = false; }
};
$('gRun').onclick = () => { loadReportsPanel(); loadIncidentsPanel(); runGroupDash().catch((e) => { $('groupMeta').innerHTML = `<span class="perr">${esc(e.message || e)}</span>`; }); };
$('scLoad').onclick = async () => {
  if (!confirm('Loading a DEV scenario replaces the entire current state. Continue?')) return;
  await api('/api/scenario/load', 'POST', { kind: $('scKind').value, seed: +$('scSeed').value });
  await reloadAll(); loadReportsPanel(); loadIncidentsPanel(); loadJournalPanel(true);
};
$('simRun').onclick = () => runSimDash();
$('iAdd').onclick = () => injectDash('reports');
$('iTeam').onclick = () => injectDash('team');
$('c2Run').onclick = () => runCompareDash();
$('jMore').onclick = () => loadJournalPanel(false);
const oldReload = reloadAll;
reloadAll = async () => { await oldReload(); loadReportsPanel().catch((e) => panelError('panelReports', e)); loadIncidentsPanel().catch((e) => panelError('panelIncidents', e)); loadJournalPanel(true).catch(() => {}); loadMetaBox().catch(() => {}); };

(async () => {
  try {
    const r = await fetch('/api/municipal/status');
    const j = await r.json();
    if (j.enforced && !j.authenticated) { showLogin(); return; }
  } catch (e) { /* status page unavailable: panels will show their errors */ }
  reloadAll();
})();
