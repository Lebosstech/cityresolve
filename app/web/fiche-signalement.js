// Fiche signalement : lecture réelle, modification autorisée et journalisée.
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
  if (r.status === 404) throw new Error('Signalement introuvable.');
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
function needAuth(fn) { return async (...a) => { try { await fn(...a); } catch (e) { if (!String(e && e.message).includes('auth')) throw e; } }; }

let current = null;

function statusPill(r) {
  if (r.verificationNote) return `<span class="pill st-valide-humain">Vérifié (humain)</span>`;
  return `<span class="pill st-propose">À vérifier</span>`;
}

function render(j) {
  const r = j.report;
  current = r;
  $('crumb').innerHTML = `Signalements › ${esc(r.id)}`;
  const isMedia = /^[0-9a-f]{24}$/.test(r.photo || '');
  const photo = isMedia
    ? `<a href="/api/photos/${esc(r.photo)}" target="_blank" rel="noopener"><img src="/api/photos/${esc(r.photo)}" alt="photo du signalement" style="max-width:100%;border-radius:10px"></a>
       <p class="muted">${j.photoMeta ? `${esc(j.photoMeta.mime || '')} · ${j.photoMeta.size} octets · reçu(e) le ${esc(new Date(j.photoMeta.createdAt).toLocaleString('fr-FR'))}` : 'média téléversé'}</p>`
    : '<p class="empty">Aucune photo — état vide (aucune image fabriquée).</p>';
  const fams = (j.subunits || []).map((u) => u.family);
  const uniqFams = [...new Set(fams)];
  const famLabel = { 'voirie-nid': 'Voirie', 'eclairage': 'Éclairage public', 'eau': 'Drainage', 'electricite': 'Électricité', 'assainissement': 'Assainissement', 'dechets': 'Propreté', 'inconnu': 'Inconnu' };
  const unknown = [];
  if (r.severityHint === null || r.severityHint === undefined) unknown.push('gravité');
  if (r.exposureHint === null || r.exposureHint === undefined) unknown.push('exposition');
  if (!r.gpsLat) unknown.push('position GPS exacte');
  const when = r.receivedAt ? new Date(r.receivedAt).toLocaleString('fr-FR') : 'scénario DEV (sans heure de réception)';
  $('ficheBody').innerHTML = `
  <section class="card"><div class="btn-row">
    <button class="btn ghost" id="backBtn">← Retour aux signalements</button>
    <span class="pill st-info" style="background:#e0f2fe;color:#075985;border-radius:14px;padding:3px 10px;font-size:11.5px;font-weight:700">Un signalement peut contenir plusieurs problèmes : ${uniqFams.length} détecté(s) ici (${uniqFams.map((f) => esc(famLabel[f] || f)).join(' + ') || 'aucun'}).</span>
    <span style="flex:1"></span>
    <button class="btn ghost" id="editBtn">✏ Modifier</button>
    <button class="btn primary" id="verifyBtn">✓ Mettre à jour le statut</button>
  </div></section>
  <section class="row2">
    <div>
      <div class="card"><h2>Photo ${isMedia ? '(1 photo)' : ''}</h2>${photo}${isMedia ? '<div class="btn-row"><button class="btn primary" id="visionBtn">Analyser la photo (IA)</button></div><p class="muted" id="visionMsg"></p>' : ''}</div>
      <div class="card"><h2>Description</h2><p>« ${esc(r.text)} »</p>
      <p class="muted">Texte original exact — aucune reformulation IA ne le remplace.</p></div>
      <div class="card"><h2>Problèmes associés (${(j.subunits || []).length})</h2>
      ${((j.subunits || []).map((u) => `<span class="chip">${esc(famLabel[u.family] || u.family)}</span> <span class="muted">${esc(u.id)}</span>`).join(' ') || '<p class="empty">aucun</p>')}
      <p class="muted">Origine conservée (ORIGINE:FAMILLE) ; un problème secondaire ne disparaît jamais quand un autre est traité.</p></div>
      ${j.extraction ? `<div class="card"><h2>Extraction IA (à vérifier)</h2><pre class="dump">${esc(JSON.stringify(j.extraction, null, 1))}</pre></div>` : ''}
      ${j.visualAnalysis ? `<div class="card"><h2>Analyse visuelle IA (à vérifier)</h2><pre class="dump">${esc(JSON.stringify(j.visualAnalysis.analysis || j.visualAnalysis, null, 1))}</pre></div>` : ''}
    </div>
    <div>
      <div class="card"><h2>Informations générales</h2>
        <p><b>N° de signalement</b> : ${esc(r.id)} <button class="link" id="copyId">copier</button></p>
        <p><b>Source</b> : ${esc(r.source)} ${r.source === 'manuel' ? '(citoyen / manuel)' : '(scénario DEV)'}</p>
        <p><b>Date</b> : ${esc(when)}</p>
        <p><b>Statut de vérification</b> : ${statusPill(r)}</p>
        ${r.verificationNote ? `<p class="muted">Note : ${esc(r.verificationNote)}${r.verifiedAt ? ' (' + esc(new Date(r.verifiedAt).toLocaleString('fr-FR')) + ')' : ''}</p>` : ''}
      </div>
      <div class="card"><h2>Localisation</h2>
        <p>Position fictive : <b>(${Number(r.x).toFixed(1)}, ${Number(r.y).toFixed(1)}) km</b> — grille 5×5, pas une adresse réelle.</p>
        ${r.gpsLat ? `<p>Relevé GPS navigateur : ${Number(r.gpsLat).toFixed(5)}, ${Number(r.gpsLon).toFixed(5)}${r.gpsAccuracy != null ? ` (±${Math.round(r.gpsAccuracy)} m)` : ''} — fourni par le déclarant.</p>` : '<p class="muted">Aucune position GPS (saisie manuelle sur la grille).</p>'}
        <p class="muted">Adresse / quartier / commune : non disponibles (aucune adresse déclarée, aucune géocodification).</p>
      </div>
      <div class="card"><h2>Gravité et exposition</h2>
        <p>Gravité déclarée : <b>${r.severityHint === null || r.severityHint === undefined ? 'Inconnue' : 'S' + r.severityHint}</b></p>
        <p>Exposition déclarée : <b>${r.exposureHint === null || r.exposureHint === undefined ? 'Inconnue' : 'E' + r.exposureHint}</b></p>
        <p class="muted">Jamais déduites de la catégorie ; valeurs contradictoires conservées, jamais moyennées.</p>
      </div>
      <div class="card"><h2>Informations inconnues conservées</h2>
        <p>${unknown.length ? 'Champs non déterminés : <b>' + unknown.map(esc).join(', ') + '</b>. ' : 'Aucun champ inconnu. '}Une vérification humaine est requise avant toute affectation opérationnelle.</p>
      </div>
    </div>
  </section>
  <section class="row2">
    <div class="card"><h2>Incidents associés (${j.linkedIncidents.length})</h2>
      ${j.linkedIncidents.map((i) => `<p><b>${esc(i.id)}</b> — ${esc(i.domain)} — gravité ${i.severity === null ? 'inconnue' : 'S' + i.severity} <a class="link" href="/municipal/decoupage">voir le découpage →</a></p>`).join('') || '<p class="empty">Aucun incident lié (regroupement en attente).</p>'}
    </div>
    <div class="card"><h2>Historique</h2>
      <ul class="timeline">${(j.history || []).map((e) => {
        const d = e.at ? new Date(e.at) : null;
        return `<li><span class="tico">•</span><div><b>${esc(e.label)}</b><br><span class="muted">${esc(e.detail || '')}</span></div><time>${esc(d ? d.toLocaleString('fr-FR') : '?')}</time></li>`;
      }).join('') || '<li class="empty">Aucun événement lié.</li>'}</ul>
      <p class="muted">Donnée fictive — journal municipal horodaté.</p>
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
  msg.textContent = 'Analyse visuelle en cours (appel réel)…';
  try {
    const j = await api('/api/meta/analyze-image', 'POST', { reportId: current.id });
    msg.textContent = `Analyse enregistrée (modèle ${j.model || '?'}). Rechargement…`;
    await load();
  } catch (e) {
    if (String(e && e.message).includes('auth')) return;
    msg.innerHTML = `<span class="perr">Analyse impossible : ${esc(e.message || e)}</span>`;
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
      note.innerHTML = 'Enregistré. Regroupement non relancé : <a class="link" href="/municipal/decoupage">re-regrouper depuis la page Découpage</a> pour propager.';
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
        else $('loginErr').textContent = 'Jeton invalide.';
      };
      return;
    }
  } catch (e) { /* la fiche affichera l'erreur */ }
  try { await load(); } catch (e) {
    if (!String(e && e.message).includes('auth')) $('ficheBody').innerHTML = `<div class="card"><p class="perr">${esc(e.message || e)}</p><p><a class="link" href="/municipal/dashboard">← Retour au tableau de bord</a></p></div>`;
  }
})();
