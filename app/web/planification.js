// Planning page: real data only, genuine actions.
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
function fmtT(m) { const d = Math.floor(m / 1440), h = String(Math.floor(m % 1440 / 60)).padStart(2, '0'), mm = String(m % 60).padStart(2, '0'); return `D${d} ${h}:${mm}`; }
function fmtDur(min) { const h = Math.floor(min / 60), m = min % 60; return h > 0 ? `${h} h${m ? ' ' + m + ' min' : ''}` : `${m} min`; }

let overview = null;

async function loadAll() {
  newCtrl();
  const j = await api('/api/municipal/plan/overview');
  overview = j;
  const avail = j.teams.filter((t) => t.available);
  $('kpiTeams').innerHTML = `<span class="kico">👥</span><div><b>${avail.length}</b><span class="klab">teams available</span><span class="ksub">of ${j.teams.length} (simulated)</span></div>`;
  $('kpiBudget').innerHTML = `<span class="kico">💰</span><div style="flex:1"><b>120</b><span class="klab">Budget (fictitious units)</span><div class="budget-bar"><i style="width:${Math.min(100, 100 * (j.plan ? j.plan.totalCost : 0) / 120).toFixed(1)}%"></i></div><span class="ksub">committed ${j.plan ? j.plan.totalCost.toFixed(1) : '0.0'} · remaining ${(120 - (j.plan ? j.plan.totalCost : 0)).toFixed(1)}</span></div>`;
  $('kpiTodo').innerHTML = `<span class="kico">⚠</span><div><b>${j.counts.planifiable}</b><span class="klab">incidents to plan</span><span class="ksub">of ${j.incidents.length} incidents (+${j.counts['a-verifier']} to verify, ${j.counts['escalade-s5']} S5)</span></div>`;
  $('kpiSim').innerHTML = j.sim
    ? `<span class="kico">🧪</span><div><b>${j.sim.q === null || j.sim.q === undefined ? '—' : Number(j.sim.q).toFixed(1)}</b><span class="klab">Simulated Q</span> <span class="tag calc">DEV</span><span class="ksub">${j.sim.feasible ? 'feasible' : 'infeasible (see violations)'} </span></div>`
    : `<span class="kico">🧪</span><div><b>—</b><span class="klab">Simulated Q</span> <span class="tag calc">DEV</span><span class="ksub">run the simulation</span></div>`;
  renderTodo();
  // Teams
  const availList = j.teams.filter((t) => t.available);
  $('teamCount').textContent = `(${availList.length}/${j.teams.length})`;
  $('teamList').innerHTML = j.teams.map((t) =>
    `<div class="card sub" style="margin-top:10px"><b>${esc(t.id)}</b> ${t.available ? '<span class="pill st-valide-humain">Available</span>' : '<span class="pill st-rejete-humain">Unavailable (simulated outage)</span>'}<br><span class="muted">Skills: ${(t.domains || []).map(esc).join(', ')}</span><br><span class="muted">Planned load: ${t.taskCount} task(s) · ${fmtDur(t.estimatedMin)} · window 08:00–16:00 (simulated)</span></div>`
  ).join('');
  renderPlan();
  renderUnassigned();
}

function renderTodo() {
  const f = $('todoFilter').value;
  const rows = overview.incidents.filter((i) => f === 'all' || i.status === f);
  $('todoList').innerHTML = rows.map((i) =>
    `<li><span class="tico">${i.status === 'escalade-s5' ? '🚨' : '⚠'}</span><div><b>${esc(i.incidentId)} — ${esc(i.label.split('·')[0])}</b><br><span class="muted">${esc(i.lieu)} · severity ${i.severity === null ? 'unknown (verification required)' : 'S' + i.severity} · ${i.dureeEstimeeMin === null ? 'duration not estimable' : '≈' + fmtDur(i.dureeEstimeeMin)} · deadline ${i.echeanceMin === -1 ? 'escalation' : i.echeanceMin === -2 ? 'to verify' : fmtT(i.echeanceMin)}</span><br><span class="pill p-${esc(i.priority)}">${esc(i.priorityLabel)}</span>${i.motif ? ` <span class="muted">${esc(i.motif)}</span>` : ''}</div><time>${esc(i.status)}</time></li>`
  ).join('') || '<li class="empty">No incidents in this filter.</li>';
}

function renderPlan() {
  const tb = $('planTable').querySelector('tbody');
  const p = overview.plan;
  if (!p || !p.tasks || !p.tasks.length) {
    tb.innerHTML = '<tr><td colspan="7" class="empty">No plan — run "Optimize the plan".</td></tr>';
    $('planMeta').textContent = overview.plan ? '' : '';
  } else {
    const byId = {};
    overview.incidents.forEach((i) => { byId[i.incidentId] = i; });
    tb.innerHTML = p.tasks.map((t, idx) =>
      `<tr><td>${idx + 1}</td><td><b>${esc(t.incidentId)}</b></td><td><span class="pill p-${esc((byId[t.incidentId] || {}).priority || 'a-verifier')}">${esc((byId[t.incidentId] || {}).priorityLabel || '?')}</span></td><td>${esc(t.teamId)}</td><td>${fmtDur(t.endMin - t.startMin)}</td><td>${t.travelKm.toFixed(1)} km</td><td>${t.cost.toFixed(1)}</td></tr>`
    ).join('');
  }
  if (p) {
    $('planMeta').innerHTML = `${esc(p.planId)} (v${p.version}) — Planned Q ${p.q.toFixed(1)} — cost ${p.totalCost.toFixed(1)}/120 — feasible: ${p.feasible ? 'yes' : '<b>no</b>'} — validation: ${esc(overview.plan.validation || 'pending (human)')}. ${p.violations.length ? '<span class="perr">Violations: ' + p.violations.map(esc).join(' ; ') + '</span>' : ''}`;
  } else {
    $('planMeta').textContent = '';
  }
  $('vState').textContent = '';
}

function renderUnassigned() {
  const rows = (overview.unassigned || []).map((u, i) => {
    const inc = (overview.incidents || []).find((x) => x.incidentId === u.incidentId) || {};
    return `<tr><td>${i + 1}</td><td><b>${esc(u.incidentId)}</b></td><td><span class="pill p-a-verifier">to review</span></td><td>${esc(u.motif)}</td></tr>`;
  }).join('');
  $('unTable').querySelector('tbody').innerHTML = rows || '<tr><td colspan="4" class="empty">None — all eligible incidents are assigned.</td></tr>';
  const p = overview.plan;
  $('constraintsBody').innerHTML = `<p>Available teams: <b>${overview.teams.filter((t) => t.available).length}/${overview.teams.length}</b> (simulated)</p>
    <p>Total budget: <b>120</b> (fictitious units)</p>
    <p>Budget used (plan): <b>${p ? p.totalCost.toFixed(1) : '0.0'}</b></p>
    <p>Remaining budget: <b>${p ? (120 - p.totalCost).toFixed(1) : '120.0'}</b></p>
    <p class="muted">Exact optimizer, bounded scope (anti-explosion guard beyond 9 incidents).</p>
    ${overview.escalations.length ? `<p class="perr">S5 in escalation (never dispatched): ${overview.escalations.map(esc).join(', ')}</p>` : ''}`;
}

$('todoFilter').onchange = renderTodo;
$('optBtn').onclick = async () => {
  $('optBtn').disabled = true;
  try {
    await api('/api/plan', 'POST', {});
    await loadAll();
  } catch (e) { $('planMeta').innerHTML = `<span class="perr">Optimisation failed: ${esc(e.message || e)}</span>`; }
  finally { $('optBtn').disabled = false; }
};
$('vYes').onclick = () => validatePlan('valide');
$('vNo').onclick = () => validatePlan('rejete');
async function validatePlan(d) {
  try {
    const j = await api('/api/plan/validate', 'POST', { decision: d });
    $('vState').textContent = `Plan ${j.validation} (human).`;
    await loadAll();
  } catch (e) { $('vState').textContent = 'Error: ' + (e.message || e); }
}
$('simRun').onclick = async () => {
  const box = $('simBox');
  try {
    const j = await api('/api/simulate', 'POST', {});
    const r = j.result;
    box.innerHTML = `<p>Simulated Q: <b>${r.q === null ? 'undefined' : r.q.toFixed(1)}</b> — feasible: ${r.feasible ? 'yes' : '<b>no</b>'} — true cost ${r.totalCost.toFixed(1)} (fictitious units)</p>` +
      (r.violations.length ? `<p><span class="perr">Violations: ${r.violations.map(esc).join(' ; ')}</span> — Q drops to 0 under the cliff rule (not frozen, see specs).</p>` : '') +
      `<p class="muted">SIMULATED interventions, not real urban interventions.</p>`;
    await loadAll();
  } catch (e) { box.innerHTML = `<p class="perr">${esc(e.message || e)}</p>`; }
};

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
  try { await loadAll(); } catch (e) {
    if (!String(e && e.message).includes('auth')) $('planMeta').innerHTML = `<span class="perr">Load failed: ${esc(e.message || e)}</span>`;
  }
})();
