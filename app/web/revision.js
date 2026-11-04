// Page Révision : oracle explicable, cas U / R1 / S5, historique versionné.
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
    else $('loginErr').textContent = 'Jeton invalide.';
  };
  // Démo : connexion en un clic, sans jeton (serveur : CITYRESOLVE_DEMO_LOGIN=true).
  // Le jeton réel n'est jamais envoyé au frontend.
  fetch('/api/municipal/status').then((r) => r.json()).then((j) => {
    if (j && j.demoLogin && !$('loginDemo')) {
      const b = document.createElement('button');
      b.className = 'btn primary'; b.id = 'loginDemo';
      b.textContent = 'Se connecter (démo)';
      b.onclick = async () => {
        const r3 = await fetch('/api/municipal/login', { method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({}) });
        if (r3.ok) location.reload();
        else $('loginErr').textContent = 'Connexion démo impossible.';
      };
      $('loginGo').after(b);
    }
  }).catch(() => {});
}
function panelError(id, e) {
  if (String(e && e.message).includes('auth') || (e && e.name === 'AbortError')) return;
  $(id).innerHTML += `<p class="perr">Échec de chargement : ${esc(e.message || e)}</p>`;
}
function fmtT(m) { const d = Math.floor(m / 1440), h = String(Math.floor(m % 1440 / 60)).padStart(2, '0'), mm = String(m % 60).padStart(2, '0'); return `J${d} ${h}:${mm}`; }

let plans = [];
let lastInject = null;

function planTable(plan) {
  if (!plan) return '<p class="empty">Aucun plan dans cette version.</p>';
  const tasks = [...(plan.tasks || [])].sort((a, b) => a.order - b.order);
  return `<div class="table-wrap"><table><thead><tr><th>#</th><th>Incident</th><th>Affectation</th><th>Priorité</th><th>Coût estimé</th></tr></thead><tbody>` +
    tasks.map((t, i) =>
      `<tr><td>${i + 1}</td><td><b>${esc(t.incidentId)}</b></td><td>${esc(t.teamId)} <span class="muted">(ordre ${t.order})</span></td><td>—</td><td>${Number(t.cost).toFixed(1)} u.</td></tr>`
    ).join('') +
    `</tbody></table></div>
    <p class="muted">Coût total estimé <b>${Number(plan.totalCost).toFixed(1)} u.</b> · Q planifié <b>${Number(plan.q).toFixed(1)}</b> · faisable : ${plan.feasible ? 'oui' : '<b>non</b>'}${(plan.violations || []).length ? ' · violations : ' + plan.violations.map(esc).join(' ; ') : ''}</p>
    <p class="muted">Unités fictives (ni euros, ni francs, ni dollars). Validation : ${esc(plan.validation || 'en attente (humain)')}.</p>`;
}

async function loadHistory() {
  const j = await api('/api/municipal/revision/history?limit=30');
  plans = j.plans || [];
  const evs = j.events || [];
  // Nouvelle information : dernier événement d'injection ou de scénario.
  const inj = evs.find((e) => e.type === 'injection' || e.type === 'equipe');
  if (inj) {
    $('newsCard').innerHTML = `<h2>Nouvelle information</h2>
      <p><b>${esc(inj.label)}</b> <span class="tag calc">${esc(inj.detail.split('·')[0] || '')}</span></p>
      <p class="muted">${esc(inj.at ? new Date(inj.at).toLocaleString('fr-FR') : '')} — enregistré dans le journal (seq ${inj.seq}).</p>
      <p class="muted">Ancienne valeur → nouvelle valeur : voir le détail de l'événement dans le journal ; seules les informations vérifiées sont reprises ci-dessous.</p>`;
  } else {
    $('newsCard').innerHTML = '<h2>Nouvelle information</h2><p class="empty">Aucune information nouvelle depuis le dernier plan. Injectez un cas ci-dessous pour démontrer U, R1 ou S5.</p>';
  }
  // Décision : dernière nécessité connue (inject reçu, sinon état courant).
  const lastNec = evs.find((e) => e.type === 'injection' || e.type === 'equipe');
  const code = lastNec ? (lastNec.detail.match(/nécessité (\S+)/) || [])[1] : null;
  const revised = lastNec ? /plan révisé/.test(lastNec.detail) : false;
  const decision = !lastNec ? ['Aucune décision en attente', 'Aucune information nouvelle à juger.', 'U'] :
    code === 'N1' ? ['Révision nécessaire', lastNec.detail + ' L\u2019équipe affectée doit être remplacée ou le plan signalé infaisable.', code] :
    code === 'N3-S5' ? ['Escalade critique', lastNec.detail + ' Aucune affectation automatique : escalade humaine immédiate.', code] :
    ['Plan conservé', lastNec.detail + ' Le plan reste en vigueur.', code || 'U'];
  $('decisionCard').innerHTML = `<h2>${esc(decision[0])}</h2>
    <p>${esc(decision[1])}</p>
    <p><span class="pill ${decision[2] === 'N1' || decision[2] === 'N3-S5' ? 'p-critique' : 'p-faible'}">${esc(decision[2])}</span>
    <span class="muted">Seuil de révision : +5 points Q (hypothèse NON GELÉE).</span></p>`;
  // Ancien / nouveau : deux dernières versions (tâches détaillées, consultables).
  const cur = plans[0] || null, prev = plans[1] || null;
  const taskRows = (p) => (p && p.detail && p.detail.tasks ? p.detail.tasks : [])
    .map((t) => `<tr><td>${esc(t.incidentId)}</td><td>${esc(t.teamId)}</td><td>${Number(t.cost).toFixed(1)}</td></tr>`).join('');
  $('oldPlanCard').innerHTML = `<h2>Ancien plan</h2><p class="muted">Plan en vigueur avant nouvelle information.</p>` +
    (prev ? `<p><b>${esc(prev.planId)} (v${prev.version})</b> · Q=${prev.q === null || prev.q === undefined ? '—' : Number(prev.q).toFixed(1)} · coût=${Number(prev.totalCost).toFixed(1)} u. · ${prev.tasks} tâches · validation : ${esc(prev.validation || 'en attente')}</p>
    <div class="table-wrap"><table><thead><tr><th>Incident</th><th>Équipe</th><th>Coût</th></tr></thead><tbody>${taskRows(prev)}</tbody></table></div>` : '<p class="empty">Pas de version antérieure (plan unique).</p>');
  $('newPlanCard').innerHTML = `<h2>Plan révisé</h2><p class="muted">Plan proposé après nouvelle information.</p>` +
    (cur ? `<p><b>${esc(cur.planId)} (v${cur.version})</b> · Q=${cur.q === null || cur.q === undefined ? '—' : Number(cur.q).toFixed(1)} · coût=${Number(cur.totalCost).toFixed(1)} u. · ${cur.tasks} tâche(s) · validation : ${esc(cur.validation || 'en attente (humain)')}</p>
    <div class="table-wrap"><table><thead><tr><th>Incident</th><th>Équipe</th><th>Coût</th></tr></thead><tbody>${taskRows(cur)}</tbody></table></div>
    <div class="btn-row"><button class="btn ghost" id="histValidate">Valider ce plan (humain)</button><button class="btn ghost" id="histReject">Rejeter</button></div>` : '<p class="empty">Aucun plan.</p>');
  const hv = $('histValidate'), hr = $('histReject');
  if (hv) hv.onclick = () => validateHistPlan('valide');
  if (hr) hr.onclick = () => validateHistPlan('rejete');
  // Modifications : comparatif tâches par incident entre les deux versions.
  if (cur && cur.detail && prev && prev.detail) {
    const a = new Map(cur.detail.tasks.map((t) => [t.incidentId, t.teamId]));
    const b = new Map(prev.detail.tasks.map((t) => [t.incidentId, t.teamId]));
    let changed = 0; const added = [], removed = [];
    for (const [id, tm] of a) { if (!b.has(id)) added.push(id); else if (b.get(id) !== tm) changed++; }
    for (const id of b.keys()) { if (!a.has(id)) removed.push(id); }
    const dq = (cur.q ?? 0) - (prev.q ?? 0), dc = cur.totalCost - prev.totalCost;
    $('diffCard').innerHTML = `<h2>Principales modifications</h2>
      <ul><li>Affectations modifiées : <b>${changed}</b></li>
      <li>Incidents ajoutés : <b>${added.length}</b>${added.length ? ' (' + added.map(esc).join(', ') + ')' : ''}</li>
      <li>Incidents retirés : <b>${removed.length}</b>${removed.length ? ' (' + removed.map(esc).join(', ') + ')' : ''}</li>
      <li>Coût estimé avant/après : <b>${Number(prev.totalCost).toFixed(1)} → ${Number(cur.totalCost).toFixed(1)} u.</b> (${dc >= 0 ? '+' : ''}${dc.toFixed(1)})</li>
      <li>Différence de Q : <b>${dq >= 0 ? '+' : ''}${dq.toFixed(1)}</b> (calculable, pas une preuve)</li></ul>
      <p class="muted">Motif : voir la décision ci-dessus. Une baisse de coût n'est jamais présentée comme un gain de Q.</p>`;
    $('globCard').innerHTML = `<h2>Comparaison globale</h2>
      <ul><li>Affectations : <b>${prev.tasks} → ${cur.tasks}</b></li>
      <li>Coût total : <b>${Number(prev.totalCost).toFixed(1)} → ${Number(cur.totalCost).toFixed(1)} u.</b></li></ul>`;
  } else {
    $('diffCard').innerHTML = '<h2>Principales modifications</h2><p class="empty">Deux versions de plan sont nécessaires pour comparer (injectez puis replanifiez).</p>';
    $('globCard').innerHTML = '<h2>Comparaison globale</h2><p class="empty">En attente d\u2019une révision.</p>';
  }
  // Journal
  $('histList').innerHTML = evs.map((e) => {
    const d = e.at ? new Date(e.at) : null;
    const when = d ? d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }) : '?';
    return `<li><span class="tico">•</span><div><b>${esc(e.label)}</b><br><span class="muted">${esc(e.detail || '')}</span></div><time>${esc(when)}</time></li>`;
  }).join('') || '<li class="empty">Aucun événement de révision.</li>';
}

async function inject(kind) {
  const box = $('injOut');
  box.innerHTML = '<p class="muted">Injection en cours…</p>';
  try {
    let j;
    if (kind === 'team') {
      // Panne de l'équipe réellement affectée au plan courant (cas R1
      // reproductible : l'oracle doit répondre N1 avec réaffectation).
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
    box.innerHTML = `<p><b>Nécessité ${esc(n.code)}</b> — ${n.necessary ? 'révision requise' : 'stabilité (pas de modification injustifiée)'} — ${esc(n.detail)}</p>` +
      (j.diff ? `<p>Changement : ${j.diff.material ? '<b>matériel</b>' : 'cosmétique'} — ${esc(j.diff.detail)}</p>` : '') +
      (j.plan ? `<p>Nouveau plan adopté : Q=${j.plan.q.toFixed(1)}, coût=${j.plan.totalCost.toFixed(1)}.</p>` : '<p class="muted">Plan inchangé (S5 : escalade humaine, pas de réaffectation).</p>');
    // Rafraîchir l'ancien/nouveau à partir de l'historique + réponse.
    await loadHistory();
    if (j.plan && j.oldPlan) showInjectPlans(j.oldPlan, j.plan, j.diff);
    else if (j.plan && window.__prevPlan) showInjectPlans(window.__prevPlan, j.plan, j.diff);
  } catch (e) { box.innerHTML = `<p class="perr">${esc(e.message || e)}</p>`; }
}

function showInjectPlans(oldPlan, newPlan, diff) {
  const row = (t) => `<tr><td>${esc(t.incidentId)}</td><td>${esc(t.teamId)}</td><td>${Number(t.cost).toFixed(1)}</td></tr>`;
  $('oldPlanCard').innerHTML = `<h2>Ancien plan</h2><p class="muted">${esc(oldPlan.planId || '')} (v${oldPlan.version || '?'}) — Q=${Number(oldPlan.q).toFixed(1)}, coût=${Number(oldPlan.totalCost).toFixed(1)} u.</p>
    <div class="table-wrap"><table><thead><tr><th>Incident</th><th>Équipe</th><th>Coût</th></tr></thead><tbody>${oldPlan.tasks.map(row).join('')}</tbody></table></div>`;
  $('newPlanCard').innerHTML = `<h2>Plan révisé</h2><p class="muted">${esc(newPlan.planId || '')} (v${newPlan.version || '?'}) — Q=${Number(newPlan.q).toFixed(1)}, coût=${Number(newPlan.totalCost).toFixed(1)} u.</p>
    <div class="table-wrap"><table><thead><tr><th>Incident</th><th>Équipe</th><th>Coût</th></tr></thead><tbody>${newPlan.tasks.map(row).join('')}</tbody></table></div>`;
  const a = new Map(newPlan.tasks.map((t) => [t.incidentId, t.teamId]));
  const b = new Map(oldPlan.tasks.map((t) => [t.incidentId, t.teamId]));
  let changed = 0; const added = [], removed = [];
  for (const [id, tm] of a) { if (!b.has(id)) added.push(id); else if (b.get(id) !== tm) changed++; }
  for (const id of b.keys()) { if (!a.has(id)) removed.push(id); }
  const dq = newPlan.q - oldPlan.q, dc = newPlan.totalCost - oldPlan.totalCost;
  $('diffCard').innerHTML = `<h2>Principales modifications</h2>
    <ul><li>Affectations modifiées : <b>${changed}</b></li>
    <li>Incidents ajoutés : <b>${added.length}</b>${added.length ? ' (' + added.map(esc).join(', ') + ')' : ''}</li>
    <li>Incidents retirés : <b>${removed.length}</b>${removed.length ? ' (' + removed.map(esc).join(', ') + ')' : ''}</li>
    <li>Coût estimé avant/après : <b>${Number(oldPlan.totalCost).toFixed(1)} → ${Number(newPlan.totalCost).toFixed(1)} u.</b></li>
    <li>Différence de Q : <b>${dq >= 0 ? '+' : ''}${dq.toFixed(1)}</b></li>
    <li>Motif : ${diff ? esc(diff.detail) : '—'}</li></ul>`;
  $('globCard').innerHTML = `<h2>Comparaison globale</h2>
    <ul><li>Affectations : <b>${oldPlan.tasks.length} → ${newPlan.tasks.length}</b></li>
    <li>Coût total : <b>${Number(oldPlan.totalCost).toFixed(1)} → ${Number(newPlan.totalCost).toFixed(1)} u.</b></li>
    <li>Q planifié : <b>${Number(oldPlan.q).toFixed(1)} → ${Number(newPlan.q).toFixed(1)}</b></li></ul>
    <p class="muted">Réviser n'améliore pas toujours le Q (cas R1 : faisabilité restaurée, Q en baisse).</p>`;
}

async function validateHistPlan(d) {
  try {
    await api('/api/plan/validate', 'POST', { decision: d });
    await loadHistory();
  } catch (e) {
    const box = $('histList');
    if (box) box.innerHTML = `<li class="perr">Validation impossible : ${esc(e.message || e)}</li>`;
  }
}

// Capture du plan courant avant injection (pour l'ancien/nouveau).
$('injU').onclick = async () => { window.__prevPlan = (await api('/api/municipal/plan/overview')).plan; inject('ordinary'); };
$('injR1').onclick = async () => { window.__prevPlan = (await api('/api/municipal/plan/overview')).plan; inject('team'); };
$('injS5').onclick = async () => { window.__prevPlan = (await api('/api/municipal/plan/overview')).plan; inject('s5'); };

// Recherche + alertes + aide : mêmes endpoints que le tableau de bord.
async function loadSearch(q) {
  const box = $('qResults');
  if (!q || q.trim().length < 2) { box.hidden = true; return; }
  try {
    const j = await api('/api/municipal/dashboard/search?q=' + encodeURIComponent(q.trim()) + '&limit=8');
    box.innerHTML = j.results.map((r) =>
      `<div data-kind="${esc(r.kind)}" data-id="${esc(r.id)}"><b>${esc(r.id)}</b> <span class="muted">[${esc(r.kind)}]</span><br><span class="muted">${esc(String(r.text || '').slice(0, 70))}</span></div>`).join('')
      || '<div class="muted">Aucun résultat.</div>';
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
      ? `<div class="alert">⚠ ${s5} incident(s) S5 en escalade humaine — jamais dispatché(s) automatiquement.</div>`
      : '<div class="alert" style="background:#f0fdf4;border-color:#bbf7d0;color:#15803d">Aucune escalade S5 en cours.</div>';
    box.hidden = false;
    setTimeout(() => { box.hidden = true; }, 6000);
  } catch (e) { /* silencieux */ }
};
$('helpBtn').onclick = () => { $('helpModal').hidden = false; };
$('helpClose').onclick = () => { $('helpModal').hidden = true; };
$('burger').onclick = () => { $('sidebar').classList.toggle('open'); };

(async () => {
  try {
    const r = await fetch('/api/municipal/status');
    const j = await r.json();
    if (j.enforced && !j.authenticated) { showLogin(); return; }
  } catch (e) { /* les panneaux afficheront leurs erreurs */ }
  newCtrl();
  try { await loadHistory(); } catch (e) {
    if (!String(e && e.message).includes('auth')) $('newsCard').innerHTML += `<p class="perr">Échec de chargement : ${esc(e.message || e)}</p>`;
  }
})();
