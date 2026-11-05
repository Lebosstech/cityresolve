// Review page: explainable oracle, U / R1 / S5 cases, versioned history.
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

let plans = [];
let lastInject = null;

function planTable(plan) {
  if (!plan) return '<p class="empty">No plan in this version.</p>';
  const tasks = [...(plan.tasks || [])].sort((a, b) => a.order - b.order);
  return `<div class="table-wrap"><table><thead><tr><th>#</th><th>Incident</th><th>Assignment</th><th>Priority</th><th>Estimated cost</th></tr></thead><tbody>` +
    tasks.map((t, i) =>
      `<tr><td>${i + 1}</td><td><b>${esc(t.incidentId)}</b></td><td>${esc(t.teamId)} <span class="muted">(order ${t.order})</span></td><td>—</td><td>${Number(t.cost).toFixed(1)} u.</td></tr>`
    ).join('') +
    `</tbody></table></div>
    <p class="muted">Total estimated cost <b>${Number(plan.totalCost).toFixed(1)} u.</b> · Planned Q <b>${Number(plan.q).toFixed(1)}</b> · feasible: ${plan.feasible ? 'yes' : '<b>no</b>'}${(plan.violations || []).length ? ' · violations: ' + plan.violations.map(esc).join(' ; ') : ''}</p>
    <p class="muted">Fictitious units (neither euros, nor francs, nor dollars). Validation: ${esc(plan.validation || 'pending (human)')}.</p>`;
}

async function loadHistory() {
  const j = await api('/api/municipal/revision/history?limit=30');
  plans = j.plans || [];
  const evs = j.events || [];
  // New information: latest injection or scenario event.
  const inj = evs.find((e) => e.type === 'injection' || e.type === 'equipe');
  if (inj) {
    $('newsCard').innerHTML = `<h2>New information</h2>
      <p><b>${esc(inj.label)}</b> <span class="tag calc">${esc(inj.detail.split('·')[0] || '')}</span></p>
      <p class="muted">${esc(inj.at ? new Date(inj.at).toLocaleString('en-US') : '')} — logged (seq ${inj.seq}).</p>
      <p class="muted">Old value → new value: see the event detail in the log; only verified information is repeated below.</p>`;
  } else {
    $('newsCard').innerHTML = '<h2>New information</h2><p class="empty">No new information since the last plan. Inject a case below to demonstrate U, R1 or S5.</p>';
  }
  // Decision: latest known necessity (injection received, otherwise current state).
  const lastNec = evs.find((e) => e.type === 'injection' || e.type === 'equipe');
  const code = lastNec ? (lastNec.detail.match(/necessity (\S+)/) || [])[1] : null;
  const revised = lastNec ? /plan revised/.test(lastNec.detail) : false;
  const decision = !lastNec ? ['No decision pending', 'No new information to judge.', 'U'] :
    code === 'N1' ? ['Review required', lastNec.detail + ' The affected team must be replaced or the plan flagged infeasible.', code] :
    code === 'N3-S5' ? ['Critical escalation', lastNec.detail + ' No automatic assignment: immediate human escalation.', code] :
    ['Plan kept', lastNec.detail + ' The plan remains in force.', code || 'U'];
  $('decisionCard').innerHTML = `<h2>${esc(decision[0])}</h2>
    <p>${esc(decision[1])}</p>
    <p><span class="pill ${decision[2] === 'N1' || decision[2] === 'N3-S5' ? 'p-critique' : 'p-faible'}">${esc(decision[2])}</span>
    <span class="muted">Review threshold: +5 Q points (NOT FROZEN hypothesis).</span></p>`;
  // Old / new: last two versions (detailed, viewable tasks).
  const cur = plans[0] || null, prev = plans[1] || null;
  const taskRows = (p) => (p && p.detail && p.detail.tasks ? p.detail.tasks : [])
    .map((t) => `<tr><td>${esc(t.incidentId)}</td><td>${esc(t.teamId)}</td><td>${Number(t.cost).toFixed(1)}</td></tr>`).join('');
  $('oldPlanCard').innerHTML = `<h2>Old plan</h2><p class="muted">Plan in force before the new information.</p>` +
    (prev ? `<p><b>${esc(prev.planId)} (v${prev.version})</b> · Q=${prev.q === null || prev.q === undefined ? '—' : Number(prev.q).toFixed(1)} · cost=${Number(prev.totalCost).toFixed(1)} u. · ${prev.tasks} tasks · validation: ${esc(prev.validation || 'pending')}</p>
    <div class="table-wrap"><table><thead><tr><th>Incident</th><th>Team</th><th>Cost</th></tr></thead><tbody>${taskRows(prev)}</tbody></table></div>` : '<p class="empty">No earlier version (single plan).</p>');
  $('newPlanCard').innerHTML = `<h2>Revised plan</h2><p class="muted">Plan proposed after the new information.</p>` +
    (cur ? `<p><b>${esc(cur.planId)} (v${cur.version})</b> · Q=${cur.q === null || cur.q === undefined ? '—' : Number(cur.q).toFixed(1)} · cost=${Number(cur.totalCost).toFixed(1)} u. · ${cur.tasks} task(s) · validation: ${esc(cur.validation || 'pending (human)')}</p>
    <div class="table-wrap"><table><thead><tr><th>Incident</th><th>Team</th><th>Cost</th></tr></thead><tbody>${taskRows(cur)}</tbody></table></div>
    <div class="btn-row"><button class="btn ghost" id="histValidate">Validate this plan (human)</button><button class="btn ghost" id="histReject">Reject</button></div>` : '<p class="empty">No plan.</p>');
  const hv = $('histValidate'), hr = $('histReject');
  if (hv) hv.onclick = () => validateHistPlan('valide');
  if (hr) hr.onclick = () => validateHistPlan('rejete');
  // Changes: per-incident task comparison between the two versions.
  if (cur && cur.detail && prev && prev.detail) {
    const a = new Map(cur.detail.tasks.map((t) => [t.incidentId, t.teamId]));
    const b = new Map(prev.detail.tasks.map((t) => [t.incidentId, t.teamId]));
    let changed = 0; const added = [], removed = [];
    for (const [id, tm] of a) { if (!b.has(id)) added.push(id); else if (b.get(id) !== tm) changed++; }
    for (const id of b.keys()) { if (!a.has(id)) removed.push(id); }
    const dq = (cur.q ?? 0) - (prev.q ?? 0), dc = cur.totalCost - prev.totalCost;
    $('diffCard').innerHTML = `<h2>Main changes</h2>
      <ul><li>Assignments changed: <b>${changed}</b></li>
      <li>Incidents added: <b>${added.length}</b>${added.length ? ' (' + added.map(esc).join(', ') + ')' : ''}</li>
      <li>Incidents removed: <b>${removed.length}</b>${removed.length ? ' (' + removed.map(esc).join(', ') + ')' : ''}</li>
      <li>Estimated cost before/after: <b>${Number(prev.totalCost).toFixed(1)} → ${Number(cur.totalCost).toFixed(1)} u.</b> (${dc >= 0 ? '+' : ''}${dc.toFixed(1)})</li>
      <li>Q difference: <b>${dq >= 0 ? '+' : ''}${dq.toFixed(1)}</b> (computable, not proof)</li></ul>
      <p class="muted">Reason: see the decision above. A cost decrease is never presented as a Q gain.</p>`;
    $('globCard').innerHTML = `<h2>Overall comparison</h2>
      <ul><li>Assignments: <b>${prev.tasks} → ${cur.tasks}</b></li>
      <li>Total cost: <b>${Number(prev.totalCost).toFixed(1)} → ${Number(cur.totalCost).toFixed(1)} u.</b></li></ul>`;
  } else {
    $('diffCard').innerHTML = '<h2>Main changes</h2><p class="empty">Two plan versions are needed to compare (inject then replan).</p>';
    $('globCard').innerHTML = '<h2>Overall comparison</h2><p class="empty">Awaiting a review.</p>';
  }
  // Log
  $('histList').innerHTML = evs.map((e) => {
    const d = e.at ? new Date(e.at) : null;
    const when = d ? d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : '?';
    return `<li><span class="tico">•</span><div><b>${esc(e.label)}</b><br><span class="muted">${esc(e.detail || '')}</span></div><time>${esc(when)}</time></li>`;
  }).join('') || '<li class="empty">No review events.</li>';
}

async function inject(kind) {
  const box = $('injOut');
  box.innerHTML = '<p class="muted">Injection in progress…</p>';
  try {
    let j;
    if (kind === 'team') {
      // Outage of the team actually assigned in the current plan (R1 case
      // reproducible: the oracle must answer N1 with reassignment).
      const ov = await api('/api/municipal/plan/overview');
      const first = (ov.plan && ov.plan.tasks && ov.plan.tasks[0]) || null;
      const tid = first ? first.teamId : 'equipe-1';
      j = await api('/api/inject', 'POST', { type: 'team_down', teamId: tid });
    } else if (kind === 's5') {
      j = await api('/api/inject', 'POST', { type: 'reports', reports: [{ text: 'immeuble effondrement rue du pont personnes piegees urgence', category: 'coupure-electrique', x: 0.5, y: 4.5, t: 900, severityHint: 5, exposureHint: 3 }] });
    } else {
      j = await api('/api/inject', 'POST', { type: 'reports', reports: [{ text: 'nid de poule rue des lilas chaussee abimee', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 540, severityHint: 2, exposureHint: 1 }] });
    }
    const n = j.necessity;
    lastInject = j;
    box.innerHTML = `<p><b>Necessity ${esc(n.code)}</b> — ${n.necessary ? 'review required' : 'stability (no unjustified change)'} — ${esc(n.detail)}</p>` +
      (j.diff ? `<p>Change: ${j.diff.material ? '<b>material</b>' : 'cosmetic'} — ${esc(j.diff.detail)}</p>` : '') +
      (j.plan ? `<p>New plan adopted: Q=${j.plan.q.toFixed(1)}, cost=${j.plan.totalCost.toFixed(1)}.</p>` : '<p class="muted">Plan unchanged (S5: human escalation, no reassignment).</p>');
    // Refresh old/new from history + response.
    await loadHistory();
    if (j.plan && j.oldPlan) showInjectPlans(j.oldPlan, j.plan, j.diff);
    else if (j.plan && window.__prevPlan) showInjectPlans(window.__prevPlan, j.plan, j.diff);
  } catch (e) { box.innerHTML = `<p class="perr">${esc(e.message || e)}</p>`; }
}

function showInjectPlans(oldPlan, newPlan, diff) {
  const row = (t) => `<tr><td>${esc(t.incidentId)}</td><td>${esc(t.teamId)}</td><td>${Number(t.cost).toFixed(1)}</td></tr>`;
  $('oldPlanCard').innerHTML = `<h2>Old plan</h2><p class="muted">${esc(oldPlan.planId || '')} (v${oldPlan.version || '?'}) — Q=${Number(oldPlan.q).toFixed(1)}, cost=${Number(oldPlan.totalCost).toFixed(1)} u.</p>
    <div class="table-wrap"><table><thead><tr><th>Incident</th><th>Team</th><th>Cost</th></tr></thead><tbody>${oldPlan.tasks.map(row).join('')}</tbody></table></div>`;
  $('newPlanCard').innerHTML = `<h2>Revised plan</h2><p class="muted">${esc(newPlan.planId || '')} (v${newPlan.version || '?'}) — Q=${Number(newPlan.q).toFixed(1)}, cost=${Number(newPlan.totalCost).toFixed(1)} u.</p>
    <div class="table-wrap"><table><thead><tr><th>Incident</th><th>Team</th><th>Cost</th></tr></thead><tbody>${newPlan.tasks.map(row).join('')}</tbody></table></div>`;
  const a = new Map(newPlan.tasks.map((t) => [t.incidentId, t.teamId]));
  const b = new Map(oldPlan.tasks.map((t) => [t.incidentId, t.teamId]));
  let changed = 0; const added = [], removed = [];
  for (const [id, tm] of a) { if (!b.has(id)) added.push(id); else if (b.get(id) !== tm) changed++; }
  for (const id of b.keys()) { if (!a.has(id)) removed.push(id); }
  const dq = newPlan.q - oldPlan.q, dc = newPlan.totalCost - oldPlan.totalCost;
  $('diffCard').innerHTML = `<h2>Main changes</h2>
    <ul><li>Assignments changed: <b>${changed}</b></li>
    <li>Incidents added: <b>${added.length}</b>${added.length ? ' (' + added.map(esc).join(', ') + ')' : ''}</li>
    <li>Incidents removed: <b>${removed.length}</b>${removed.length ? ' (' + removed.map(esc).join(', ') + ')' : ''}</li>
    <li>Estimated cost before/after: <b>${Number(oldPlan.totalCost).toFixed(1)} → ${Number(newPlan.totalCost).toFixed(1)} u.</b></li>
    <li>Q difference: <b>${dq >= 0 ? '+' : ''}${dq.toFixed(1)}</b></li>
    <li>Reason: ${diff ? esc(diff.detail) : '—'}</li></ul>`;
  $('globCard').innerHTML = `<h2>Overall comparison</h2>
    <ul><li>Assignments: <b>${oldPlan.tasks.length} → ${newPlan.tasks.length}</b></li>
    <li>Total cost: <b>${Number(oldPlan.totalCost).toFixed(1)} → ${Number(newPlan.totalCost).toFixed(1)} u.</b></li>
    <li>Planned Q: <b>${Number(oldPlan.q).toFixed(1)} → ${Number(newPlan.q).toFixed(1)}</b></li></ul>
    <p class="muted">Reviewing does not always improve Q (R1 case: feasibility restored, Q lower).</p>`;
}

async function validateHistPlan(d) {
  try {
    await api('/api/plan/validate', 'POST', { decision: d });
    await loadHistory();
  } catch (e) {
    const box = $('histList');
    if (box) box.innerHTML = `<li class="perr">Validation failed: ${esc(e.message || e)}</li>`;
  }
}

// Capture the current plan before injection (for old/new).
$('injU').onclick = async () => { window.__prevPlan = (await api('/api/municipal/plan/overview')).plan; inject('ordinary'); };
$('injR1').onclick = async () => { window.__prevPlan = (await api('/api/municipal/plan/overview')).plan; inject('team'); };
$('injS5').onclick = async () => { window.__prevPlan = (await api('/api/municipal/plan/overview')).plan; inject('s5'); };

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
  newCtrl();
  try { await loadHistory(); } catch (e) {
    if (!String(e && e.message).includes('auth')) $('newsCard').innerHTML += `<p class="perr">Load failed: ${esc(e.message || e)}</p>`;
  }
})();
