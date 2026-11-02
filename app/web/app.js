// Client fin CityResolve DEV : affichage seul, toute la logique est serveur.
const $ = (id) => document.getElementById(id);
async function api(path, method = 'GET', body = null) {
  const r = await fetch(path, { method, headers: {'Content-Type':'application/json'},
    body: body ? JSON.stringify(body) : null });
  const j = await r.json();
  if (!r.ok) throw new Error(j.error || ('HTTP ' + r.status));
  return j;
}
function showError(e) {
  const b = $('errBox');
  b.textContent = 'Erreur : ' + (e && e.message ? e.message : e);
  b.hidden = false;
}
function clearError() { const b = $('errBox'); b.hidden = true; b.textContent = ''; }
const safe = (fn) => async (...a) => { try { clearError(); await fn(...a); } catch (e) { showError(e); } };
document.querySelectorAll('nav button[data-view]').forEach((b) => {
  b.onclick = () => {
    document.querySelectorAll('nav button[data-view]').forEach((x) => x.classList.remove('active'));
    b.classList.add('active');
    document.querySelectorAll('.view').forEach((v) => v.classList.remove('active'));
    $('view-' + b.dataset.view).classList.add('active');
    if (b.dataset.view === 'journal') loadJournal().catch(showError);
    if (b.dataset.view === 'dashboard') loadDashboard().catch(showError);
  };
});
function esc(s) { return String(s).replace(/[&<>"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }
function fmtT(m) { const d = Math.floor(m/1440), h = String(Math.floor(m%1440/60)).padStart(2,'0'), mm = String(m%60).padStart(2,'0'); return `J${d} ${h}:${mm}`; }

async function loadMeta() {
  const m = await api('/api/meta');
  $('metaBox').innerHTML = 'Meta : <b>' + esc(m.state) + '</b><br>' + esc(m.message);
}
async function loadPolicy() {
  const p = await api('/api/policy');
  $('polLine').textContent = `Q ${p.qWeights[0]}/${p.qWeights[1]} (provisoire), budget ${p.budget}, ${p.availability}`;
}
async function loadDashboard() {
  const reps = await api('/api/reports');
  const inc = await api('/api/incidents');
  const unk = inc.incidents.filter((i) => i.exposure === null).length;
  const s5 = inc.incidents.filter((i) => i.severity >= 5).length;
  $('dashCards').innerHTML =
    card(reps.reports.length, 'signalements <span class="tag sim">SIMULÉ</span>') +
    card(inc.incidents.length, 'incidents <span class="tag calc">CALCULÉ</span>') +
    card(unk, 'expositions inconnues <span class="tag unk">INCONNU</span>') +
    card(s5, 'S5 (escalade, hors plan)');
  drawMap(reps.reports, inc.incidents);
}
function card(n, label) { return `<div class="card"><b>${n}</b>${label}</div>`; }
function drawMap(reports, incidents) {
  const svg = $('map');
  const gOf = {};
  incidents.forEach((inc, i) => inc.reportIds.forEach((r) => (gOf[r] = i)));
  const cols = ['#1466b8','#b3261e','#2e7d32','#b87e14','#6a3fb5','#0e7c7b','#c2185b','#455a64'];
  let h = '';
  for (let i = 0; i <= 5; i++) {
    h += `<line x1="${i*100}" y1="0" x2="${i*100}" y2="500" stroke="#dfe6ec"/>`;
    h += `<line x1="0" y1="${i*100}" x2="500" y2="${i*100}" stroke="#dfe6ec"/>`;
  }
  h += '<circle cx="0" cy="500" r="7" fill="#000"/><text x="10" y="495" font-size="12">dépôt</text>';
  reports.forEach((r) => {
    const x = r.x * 100, y = 500 - r.y * 100;
    const c = cols[(gOf[r.id] || 0) % cols.length];
    h += `<circle cx="${x}" cy="${y}" r="8" fill="${c}"><title>${esc(r.id)}: ${esc(r.text)}</title></circle>`;
    h += `<text x="${x+10}" y="${y+4}" font-size="11">${esc(r.id)}</text>`;
  });
  svg.innerHTML = h;
}
async function loadReports() {
  const j = await api('/api/reports');
  $('repTable').querySelector('tbody').innerHTML = j.reports.map((r) =>
    `<tr><td>${esc(r.id)}${j.manual.includes(r.id) ? ' <span class="tag hum">MANUEL</span>' : ''}</td><td>${esc(r.text)}</td><td>${esc(r.category)}</td><td>(${r.x.toFixed(2)}, ${r.y.toFixed(2)})</td><td>${fmtT(r.t)}</td><td>${r.severityHint ?? '?'} / ${r.exposureHint === null || r.exposureHint === undefined ? '<span class="tag unk">?</span>' : r.exposureHint}</td><td>${esc(r.photo || '—')}</td></tr>`).join('');
}
function sevCell(i) {
  if (i.severity === null || i.severity === undefined) {
    return `<span class="tag unk">${i.severityStatus === 'contradictoire' ? 'CONTRADICTOIRE' : 'INCONNUE'}</span><br><span class="note">valeurs: ${esc((i.severityValues || []).join(', ') || '—')} → vérification</span>`;
  }
  return `${i.severity}${i.severity >= 5 ? ' <span class="tag hum">S5</span>' : ''}<br><span class="note">${esc(i.severityStatus)}</span>`;
}
function renderIncidents(incidents) {
  $('incTable').querySelector('tbody').innerHTML = incidents.map((i) =>
    `<tr><td>${esc(i.id)}</td><td>${i.reportIds.map(esc).join(', ')}</td><td>${sevCell(i)}</td><td>${i.exposure === null ? '<span class="tag unk">INCONNUE→E4</span>' : i.exposure}</td><td>${esc(i.domain)}${i.domainConflict ? ' <span class="tag unk">CONFLIT</span>' : ''}</td><td>${i.weight.toFixed(3)}</td><td>${i.deadline === -2 ? 'vérification requise' : i.deadline < 0 ? 'escalade' : fmtT(i.deadline)}</td><td>${i.confidence.toFixed(2)}</td></tr>`).join('');
}
async function runGroup() {
  const method = $('gMethod') ? $('gMethod').value : 'classique';
  const j = await api('/api/group', 'POST', { distMaxM: +$('pDist').value, deltaTMaxH: +$('pDt').value, simMin: +$('pSim').value, method });
  renderIncidents(j.incidents);
  const unc = (j.groups || []).filter((g) => g.uncertain);
  let uh = '';
  if (unc.length) uh += `<p class="ko">Regroupements incertains (à vérifier) :</p><ul>${unc.map((g) => `<li>${esc(g.id)} (${g.reportIds.map(esc).join(', ')}) : ${g.uncertaintyReasons.map(esc).join(' ; ')}${g.justification ? ' — modèle : ' + esc(g.justification) : ''}</li>`).join('')}</ul>`;
  if ((j.ambiguousPairs || []).length) uh += `<p class="ko">Séparations ambiguës :</p><ul>${j.ambiguousPairs.map((a) => `<li>${esc(a.a)} / ${esc(a.b)} : ${esc(a.reason)}</li>`).join('')}</ul>`;
  $('uncertBox').innerHTML = uh;
  // Regrouper invalide le plan côté serveur : vider les vues périmées.
  $('planBox').innerHTML = '';
  $('simBox').innerHTML = '';
  $('vState').textContent = '';
  const m = j.metrics;
  $('f1Box').innerHTML = m.available
    ? `<p>F1 pairwise <span class="tag calc">CALCULÉ</span> : <b>${m.pairwise.f1.toFixed(3)}</b> (P=${m.pairwise.precision.toFixed(3)}, R=${m.pairwise.recall.toFixed(3)}), B-cubed=${m.bCubedF1.toFixed(3)}. <span class="note">${esc(m.note)}</span></p>`
    : `<p class="note">Métriques indisponibles : ${esc(m.reason)}</p>`;
  loadDashboard();
}
async function runPlan() {
  const p = await api('/api/plan', 'POST', {});
  renderPlan(p);
}
function renderPlan(p) {
  let h = `<p>Plan <b>${esc(p.planId || 'sans id')}</b> (version ${p.version ?? 0}) — Q planifié <span class="tag calc">CALCULÉ</span> : <b>${p.q.toFixed(1)}</b> — coût ${p.totalCost.toFixed(1)}/120 — faisable : ${p.feasible ? '<span class="ok">oui</span>' : '<span class="ko">non</span>'}</p>`;
  h += '<table><thead><tr><th>Incident</th><th>Équipe</th><th>Ordre</th><th>Début</th><th>Fin</th><th>Coût</th><th>Justification</th></tr></thead><tbody>';
  p.tasks.forEach((t) => { h += `<tr><td>${esc(t.incidentId)}</td><td>${esc(t.teamId)}</td><td>${t.order}</td><td>${fmtT(t.startMin)}</td><td>${fmtT(t.endMin)}</td><td>${t.cost.toFixed(1)}</td><td>${esc(p.justifications[t.incidentId] || '')}</td></tr>`; });
  Object.entries(p.unassigned).forEach(([k, v]) => { h += `<tr><td>${esc(k)}</td><td colspan="5"><i>non affecté</i></td><td>${esc(v)}</td></tr>`; });
  h += '</tbody></table>';
  if (p.escalations.length) h += `<p>S5 en escalade humaine : ${p.escalations.map(esc).join(', ')} (jamais dispatchés)</p>`;
  if (p.violations.length) h += `<p class="ko">Violations : ${p.violations.map(esc).join(' ; ')}</p>`;
  $('planBox').innerHTML = h;
  $('vState').textContent = '';
}
async function validatePlan(d) {
  const j = await api('/api/plan/validate', 'POST', { decision: d });
  $('vState').innerHTML = `Plan <span class="tag hum">${esc(j.validation).toUpperCase()} (HUMAIN)</span>`;
}
async function runSim() {
  const j = await api('/api/simulate', 'POST', {});
  const r = j.result;
  let h = `<p>Q simulé <span class="tag sim">SIMULÉ</span> : <b>${r.q === null ? 'indéfini' : r.q.toFixed(1)}</b> — faisable : ${r.feasible ? '<span class="ok">oui</span>' : '<span class="ko">non'}</span> — coût vrai ${r.totalCost.toFixed(1)}</p>`;
  if (r.violations.length) h += `<p class="ko">Violations : ${r.violations.map(esc).join(' ; ')}</p>`;
  h += '<table><thead><tr><th>Incident</th><th>Vérité</th><th>R</th><th>Motif</th><th>Fin</th></tr></thead><tbody>';
  r.outcomes.forEach((o) => { h += `<tr><td>${esc(o.incidentId)}</td><td>${esc(o.truthId || '?')}${o.pure ? '' : ' <span class="tag unk">IMPUR</span>'}</td><td>${o.result}</td><td>${esc(o.reason)}</td><td>${fmtT(o.endMin)}</td></tr>`; });
  h += '</tbody></table>';
  if (r.missedTruth.length) h += `<p>Incidents vrais manqués : ${r.missedTruth.map(esc).join(', ')}</p>`;
  if (r.structurallyInfeasible.length) h += `<p>Structurellement infaisables (conservés) : ${r.structurallyInfeasible.map(esc).join(', ')}</p>`;
  h += '<p>Robustesse (plans figés) :</p><table><thead><tr><th>Durées</th><th>Coûts</th><th>Q</th><th>Faisable</th></tr></thead><tbody>';
  j.robustness.forEach((v) => { h += `<tr><td>×${v.durScale}</td><td>×${v.costScale}</td><td>${v.q === null ? '—' : v.q.toFixed(1)}</td><td>${v.feasible ? 'oui' : 'non'}</td></tr>`; });
  h += `</tbody></table><p class="note">${esc(j.note)}</p>`;
  $('simBox').innerHTML = h;
}
async function injectReports() {
  const j = await api('/api/inject', 'POST', { type: 'reports', reports: [{ text: $('iText').value, category: $('iCat').value, x: +$('iX').value, y: +$('iY').value, t: +$('iT').value, severityHint: $('iSev').value === '' ? null : +$('iSev').value, exposureHint: $('iExp').value === '' ? null : +$('iExp').value }] });
  showInject(j);
}
async function injectTeam() {
  const j = await api('/api/inject', 'POST', { type: 'team_down', teamId: 'equipe-1' });
  showInject(j);
}
async function showInject(j) {
  const n = j.necessity;
  let h = `<p>Nécessité oracle (estimations) : <b>${esc(n.code)}</b> — ${n.necessary ? 'révision requise' : 'stabilité'} — ${esc(n.detail)}</p>`;
  if (j.diff) h += `<p>Changement : ${j.diff.material ? '<b>matériel</b>' : 'cosmétique'} — ${esc(j.diff.detail)}</p>`;
  if (j.plan) h += `<p>Nouveau plan adopté <span class="tag prop">PROPOSÉ</span> : Q=${j.plan.q.toFixed(1)}, coût=${j.plan.totalCost.toFixed(1)}.</p>`;
  $('injBox').innerHTML = h;
  // Ne pas re-regrouper ici : /api/group invaliderait le plan que
  // l'oracle vient de juger stable ou de réviser. Rendre la réponse.
  if (j.incidents) renderIncidents(j.incidents);
  if (j.plan) renderPlan(j.plan);
  await loadReports();
  loadDashboard();
}
async function loadJournal() {
  const j = await api('/api/journal');
  $('jTable').querySelector('tbody').innerHTML = j.entries.map((e) =>
    `<tr><td>${e.seq}</td><td>${esc(e.at)}</td><td>${esc(e.event)}</td><td><pre class="dump">${esc(JSON.stringify(e.details || {}, null, 1))}</pre></td></tr>`).join('');
}
async function runCompare() {
  const j = await api('/api/compare', 'POST', { configs: [
    { name: 'défaut', distMaxM: 250, deltaTMaxH: 6, simMin: 0.75 },
    { name: 'strict', distMaxM: 100, deltaTMaxH: 1, simMin: 0.85 },
    { name: 'large', distMaxM: 500, deltaTMaxH: 24, simMin: 0.65 },
  ]});
  $('cTable').querySelector('tbody').innerHTML = j.rows.map((r) =>
    `<tr><td>${esc(r.config.name || '')} (${r.config.distMaxM}m, ${r.config.deltaTMaxH}h, ${r.config.simMin})</td><td>${r.groups}</td><td>${r.f1.toFixed(3)}</td><td>${r.planQ === null ? '—' : r.planQ.toFixed(1)}</td><td>${r.simQ === null ? '—' : r.simQ.toFixed(1)}</td><td>${r.feasible ? 'oui' : 'non'}</td></tr>`).join('') +
    `<tr><td colspan="6">Meta : ${esc(j.meta.state)} — ${esc(j.meta.message)}</td></tr>`;
}
async function verifyMeta() {
  const j = await api('/api/meta/verify', 'POST', {});
  const m = j.meta;
  $('metaBox').innerHTML = 'Meta : <b>' + esc(m.state) + '</b><br>' + esc(m.message) + (m.models && m.models.length ? '<br>Modèles verifies : ' + m.models.map(esc).join(', ') : '');
}
async function runExtract() {
  const j = await api('/api/meta/extract', 'POST', { reportId: $('xReport').value.trim() });
  $('xOut').textContent = JSON.stringify(j.extraction, null, 1);
}
async function runCompareMethods() {
  const j = await api('/api/compare-methods');
  const side = (s, label) => s === null ? `<p>${label} : <b>indisponible</b> (connecteur ${esc(j.metaState)} — aucun résultat simulé)</p>` :
    `<p>${label} : ${s.groups.length} groupes, F1=${s.f1 ? s.f1.f1.toFixed(3) : 'non calculé (pas de vérité)'}, Q planifié=${s.planQ === null || s.planQ === undefined ? '—' : s.planQ.toFixed(1)}, Q simulé=${s.simQ === null || s.simQ === undefined ? '—' : s.simQ.toFixed(1)}</p><ul>${s.groups.map((g) => `<li>${esc(g.id)} : ${g.reportIds.map(esc).join(', ')}${g.uncertain ? ' <span class="tag unk">INCERTAIN</span>' : ''}${g.justification ? ' — ' + esc(g.justification) : ''}</li>`).join('')}</ul>`;
  let h = '<p class="note">' + esc(j.note) + '<br>' + esc(j.truthNote) + '</p>';
  h += side(j.classique, 'CLASSIQUE (référence)');
  h += side(j.meta, 'META');
  if (j.disagreements.length) h += `<p class="ko">Désaccords entre méthodes (${j.disagreements.length}) :</p><ul>${j.disagreements.map((d) => `<li>${esc(d.a)} / ${esc(d.b)} : classique=${esc(d.classique)}, meta=${esc(d.meta)}</li>`).join('')}</ul>`;
  else if (j.metaAvailable) h += '<p>Aucun désaccord de paire entre les deux méthodes.</p>';
  h += `<p>Appels IA : ${j.metaCalls.count} appel(s), ${j.metaCalls.errors} erreur(s)/refus, latence totale ${j.metaCalls.totalLatencyMs} ms (coût monétaire : non fourni par l'API, non inventé).</p>`;
  $('c2Box').innerHTML = h;
}
$('scLoad').onclick = safe(async () => { await api('/api/scenario/load', 'POST', { kind: $('scKind').value, seed: +$('scSeed').value }); $('planBox').innerHTML = ''; $('simBox').innerHTML = ''; $('injBox').innerHTML = ''; $('vState').textContent = ''; loadDashboard(); loadReports(); await runGroup(); });
$('fAdd').onclick = safe(async () => { await api('/api/reports', 'POST', { text: $('fText').value, category: $('fCat').value, x: +$('fX').value, y: +$('fY').value, t: +$('fT').value, photo: $('fPhoto').value || null, severityHint: $('fSev').value === '' ? null : +$('fSev').value, exposureHint: $('fExp').value === '' ? null : +$('fExp').value }); await loadReports(); await runGroup(); });
$('metaVerify').onclick = safe(verifyMeta);
$('xRun').onclick = safe(runExtract);
$('c2Run').onclick = safe(runCompareMethods);
$('gRun').onclick = safe(runGroup);
$('planRun').onclick = safe(runPlan);
$('vYes').onclick = safe(() => validatePlan('valide'));
$('vNo').onclick = safe(() => validatePlan('rejete'));
$('simRun').onclick = safe(runSim);
$('iAdd').onclick = safe(injectReports);
$('iTeam').onclick = safe(injectTeam);
$('jReload').onclick = safe(loadJournal);
$('cRun').onclick = safe(runCompare);
(async () => { try { await loadMeta(); await loadPolicy(); await loadDashboard(); await loadReports(); await runGroup(); } catch (e) { showError(e); } })();
