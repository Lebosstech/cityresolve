// Page Découpage multi-problème : données réelles uniquement.
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
}
function panelError(id, e) {
  if (String(e && e.message).includes('auth') || (e && e.name === 'AbortError')) return;
  $(id).innerHTML += `<p class="perr">Échec de chargement : ${esc(e.message || e)}</p>`;
}
const famLabel = { 'voirie-nid': 'Voirie', 'eclairage': 'Éclairage public', 'eau': 'Drainage', 'electricite': 'Électricité', 'assainissement': 'Assainissement', 'dechets': 'Propreté', 'inconnu': 'Inconnu' };
const famIcon = { 'voirie-nid': '🛣', 'eclairage': '💡', 'eau': '💧', 'electricite': '⚡', 'assainissement': '🚰', 'dechets': '🗑', 'inconnu': '❓' };

let currentReportId = null;

async function loadOverview() {
  const j = await api('/api/municipal/split/overview');
  $('methodNote').textContent = `Méthode réellement utilisée : ${j.method} — ${j.groups} groupes, ${j.units} unités, ${j.incidents} incidents. ${j.multiProblemReports.length} signalement(s) multi-problème conservé(s).`;
  const sel = $('repSel');
  sel.innerHTML = j.multiProblemReports.map((id) => `<option value="${esc(id)}">${esc(id)}</option>`).join('')
    || '<option value="">(aucun multi-problème dans l\u2019état courant)</option>';
  try { $('gMethod').value = j.method; } catch (e) { /* méthode inconnue : laisser CLASSIQUE */ }
  if (!currentReportId && j.multiProblemReports.length) currentReportId = j.multiProblemReports[0];
  if (currentReportId && j.multiProblemReports.includes(currentReportId)) sel.value = currentReportId;
  else if (j.multiProblemReports.length) { currentReportId = j.multiProblemReports[0]; sel.value = currentReportId; }
  else currentReportId = null;
  if (currentReportId) await loadExample(currentReportId);
  else {
    $('originCard').innerHTML = '<h3>Signalement d\u2019origine</h3><p class="empty">Aucun signalement multi-problème dans l\u2019état courant. Chargez un scénario DEV contenant deux problèmes (ex. jouet-1 + injection).</p>';
    $('subCol').innerHTML = ''; $('incCol').innerHTML = '';
  }
  // Tableau incidents reconstruits
  const rows = j.perIncident.map((p, i) =>
    `<tr><td>${i + 1}</td><td><b>${esc('Incident ' + p.incidentId)}</b><br><span class="muted">${esc(p.domain)}</span></td><td>${esc(p.domain)}</td><td>${p.units}</td><td>(${p.x.toFixed(1)}, ${p.y.toFixed(1)}) — grille fictive</td><td><span class="pill st-${esc(p.status)}">${esc(p.status)}</span></td><td><a class="link" href="/municipal/signalements/${esc(p.origins[0] || '')}">Voir l\u2019origine →</a></td></tr>`
  ).join('');
  $('incTable').querySelector('tbody').innerHTML = rows || '<tr><td colspan="7" class="empty">Aucun incident.</td></tr>';
  $('incCountLine').textContent = `${j.incidents} incidents générés à partir de l\u2019état courant (données fictives).`;
  // Méthode
  $('methodCard').innerHTML = `<h2>Méthode de regroupement</h2>
    <p><b>Méthode</b> : ${esc(j.method)}</p>
    <p><b>Groupes</b> : ${j.groups} · <b>Unités</b> : ${j.units} · <b>Incidents</b> : ${j.incidents}</p>
    <p><b>Problèmes secondaires conservés</b> : ${j.multiProblemReports.length ? j.multiProblemReports.map(esc).join(', ') : 'aucun'}</p>
    <p><b>Incertitudes</b> :</p><ul>${j.uncertaintyReasons.map((u) => `<li>${esc(u)}</li>`).join('') || '<li class="muted">aucune signalée</li>'}</ul>
    <p><b>Justifications</b> :</p><ul>${j.justifications.map((x) => `<li>${esc(x)}</li>`).join('') || '<li class="muted">aucune</li>'}</ul>
    <p class="muted">${esc(j.note)}</p>`;
}

async function loadExample(reportId) {
  const j = await api('/api/municipal/split/report?reportId=' + encodeURIComponent(reportId));
  const isMedia = /^[0-9a-f]{24}$/.test(j.photo || '');
  $('originCard').innerHTML = `<h3>Signalement d'origine</h3>
    <p><b>N° ${esc(j.reportId)}</b> <span class="muted">· ${esc(j.category)} · ${esc(j.source)}</span></p>
    <p>« ${esc(j.text)} »</p>
    ${isMedia ? `<a href="/api/photos/${esc(j.photo)}" target="_blank" rel="noopener"><img src="/api/photos/${esc(j.photo)}" alt="photo du signalement" style="max-width:100%;border-radius:10px"></a><p class="muted">1 média</p><button class="btn ghost" id="originVision">Analyser la photo (IA)</button> <span class="muted" id="originVisionMsg"></span>` : '<p class="muted">Aucune photo.</p>'}
    <p><a class="link" href="/municipal/signalements/${esc(j.reportId)}">Fiche complète →</a></p>`;
  if (isMedia) $('originVision').onclick = () => analyzePhoto(j.reportId, 'originVision', 'originVisionMsg');
  $('subCol').innerHTML = j.subunits.map((u, i) =>
    `<div class="card sub"><h3>${famIcon[u.family] || '❓'} Sous-signalement ${i + 1}</h3>
    <p><b>${esc(famLabel[u.family] || u.family)}</b><br><span class="muted">${esc(u.id)}</span></p>
    <p><span class="pill st-a-verifier">à vérifier</span> <span class="pill st-a-verifier">gravité inconnue</span></p>
    <p class="muted">Provenance : texte d'origine. État : à vérifier avant regroupement.</p></div>`).join('');
  $('incCol').innerHTML = j.linkedIncidents.map((inc) =>
    `<div class="card sub"><h3>Incident (regroupement)</h3>
    <p><b>Incident ${esc(inc.id)}</b> <span class="tag calc">REGROUPÉ</span></p>
    <p class="muted">${esc(inc.domain)} · gravité ${inc.severity === null ? 'inconnue' : 'S' + inc.severity}</p>
    ${j.uncertaintyReasons.map((u) => `<p class="muted">⚠ ${esc(u)}</p>`).join('')}
    <p><a class="link" href="/municipal/dashboard#panelIncidents">Voir dans les incidents →</a></p></div>`).join('')
    || '<div class="card sub"><p class="empty">Aucun incident lié pour le moment (regroupement en attente).</p></div>';
}

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
async function analyzePhoto(reportId, btnId, msgId) {
  const btn = $(btnId), msg = $(msgId);
  btn.disabled = true;
  msg.textContent = 'Analyse visuelle en cours (appel réel)…';
  try {
    const j = await api('/api/meta/analyze-image', 'POST', { reportId });
    msg.innerHTML = `Analyse enregistrée (modèle ${esc(j.model || '?')}, « à vérifier »). <a class="link" href="/municipal/signalements/${esc(reportId)}">Voir la fiche →</a>`;
  } catch (e) {
    if (!String(e && e.message).includes('auth')) msg.innerHTML = `<span class="perr">Analyse impossible : ${esc(e.message || e)}</span>`;
  } finally { btn.disabled = false; }
}
async function loadMeta() {
  try {
    const j = await api('/api/meta');
    $('metaState').textContent = `État Meta : ${j.state} — modèle : ${j.model || 'aucun'} — ${j.message || ''}`;
  } catch (e) {
    if (String(e && e.message).includes('auth') || (e && e.name === 'AbortError')) return;
    $('metaState').textContent = 'État Meta : indisponible (' + (e.message || e) + ')';
  }
}
$('metaVerifyBtn').onclick = async () => {
  const btn = $('metaVerifyBtn');
  btn.disabled = true;
  $('metaState').textContent = 'État Meta : vérification en cours (appel réel GET /models)…';
  try {
    const j = await api('/api/meta/verify', 'POST', {});
    $('metaState').textContent = `État Meta : ${j.meta.state} — modèle : ${j.meta.model || 'aucun'} — ${j.meta.message || ''} (appel ${j.call.id}, ${j.call.latencyMs} ms)`;
  } catch (e) {
    if (!String(e && e.message).includes('auth')) $('metaState').textContent = 'État Meta : vérification impossible (' + (e.message || e) + ')';
  } finally { btn.disabled = false; }
};
$('repSel').onchange = () => { currentReportId = $('repSel').value || null; if (currentReportId) loadExample(currentReportId).catch((e) => panelError('originCard', e)); };
$('gRun').onclick = async () => {
  try {
    const j = await api('/api/group', 'POST', { method: $('gMethod').value });
    $('methodNote').textContent = `Regroupement ${j.method} exécuté : ${j.groups.length} groupes, ${j.incidents.length} incidents. Plan précédent invalidé (replanifier).`;
    await loadOverview();
  } catch (e) { $('methodNote').innerHTML = `<span class="perr">${esc(e.message || e)}</span>`; }
};
function panelError(id, e) {
  if (String(e && e.message).includes('auth') || (e && e.name === 'AbortError')) return;
  $(id).innerHTML += `<p class="perr">Échec de chargement : ${esc(e.message || e)}</p>`;
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
        else $('loginErr').textContent = 'Jeton invalide.';
      };
      return;
    }
  } catch (e) { /* les panneaux afficheront leurs erreurs */ }
  newCtrl();
  try { await loadOverview(); } catch (e) { panelError('originCard', e); }
  loadMeta().catch(() => {});
})();
