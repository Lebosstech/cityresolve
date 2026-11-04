// Page publique CityResolve : signalement + carte + suivi (données réelles filtrées).
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const isMediaId = (s) => /^[0-9a-f]{24}$/.test(String(s || ''));
const state = { x: null, y: null, mediaId: null, gps: null };
const DEMO_RADIUS_KM = 3.54; // demi-diagonale de la grille 5×5 : hors de ce rayon, refus honnête
function distKm(lat1, lon1, lat2, lon2) {
  const r = Math.PI / 180, dLa = (lat2 - lat1) * r;
  const dLo = (lon2 - lon1) * r * Math.cos((lat1 + lat2) / 2 * r);
  return Math.sqrt(dLa * dLa + dLo * dLo) * 111.32;
}

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
$('pGps').onclick = () => {
  clearErr();
  if (!navigator.geolocation) {
    showErr('Géolocalisation indisponible dans ce navigateur (contexte non sécurisé ?). Utilisez « Choisir sur la carte ».');
    return;
  }
  $('pCoords').textContent = 'Localisation en cours… (autorisez la position dans votre navigateur)';
  navigator.geolocation.getCurrentPosition(
    (pos) => {
      const { latitude, longitude, accuracy } = pos.coords;
      const d = distKm(latitude, longitude, ANCHOR.lat, ANCHOR.lon);
      if (d > DEMO_RADIUS_KM) {
        state.x = null; state.y = null; state.gps = null;
        $('pCoords').textContent = 'Position : non choisie (grille fictive 5×5 km)';
        showErr(`Position hors zone de démonstration (${d.toFixed(1)} km de l'ancrage, démo limitée à ${DEMO_RADIUS_KM} km). Utilisez « Choisir sur la carte ».`);
        return;
      }
      const [gx, gy] = latLngToGrid(latitude, longitude);
      state.x = gx; state.y = gy;
      state.gps = { lat: latitude, lon: longitude, accuracy: accuracy ?? null };
      $('pCoords').textContent = `Position GPS : (${gx.toFixed(1)}, ${gy.toFixed(1)}) km — grille fictive (±${Math.round(accuracy ?? -1)} m annoncés)`;
      drawMap();
    },
    (err) => {
      state.x = null; state.y = null; state.gps = null;
      const msg = err.code === err.PERMISSION_DENIED
        ? 'Géolocalisation refusée : aucune position collectée. Utilisez « Choisir sur la carte ».'
        : err.code === err.POSITION_UNAVAILABLE
          ? 'Position indisponible (GPS coupé ?). Utilisez « Choisir sur la carte ».'
          : 'Délai de localisation dépassé. Réessayez ou utilisez « Choisir sur la carte ».';
      $('pCoords').textContent = 'Position : non choisie (grille fictive 5×5 km)';
      showErr(msg);
    },
    { timeout: 10000, maximumAge: 60000 },
  );
};
$('pPick').onclick = () => { $('pickModal').hidden = false; drawPicker(); };
$('pickCancel').onclick = () => { $('pickModal').hidden = true; };
$('pickOk').onclick = () => {
  if (state.x === null) { showErr('Cliquez sur la grille pour choisir une position.'); return; }
  state.gps = null; // saisie manuelle : pas de relevé GPS associé
  $('pCoords').textContent = `Position : (${state.x.toFixed(1)}, ${state.y.toFixed(1)}) km — grille fictive (saisie manuelle)`;
  $('pickModal').hidden = true;
  drawMap();
};
let mapPick = null, pickDot = null;
function drawPicker() {
  if (typeof L === 'undefined') {
    $('pickMap').innerHTML = '<p class="map-offline">Fond de carte indisponible (connexion requise). Saisie au clavier : utilisez la console municipale.</p>';
    return;
  }
  if (!mapPick) {
    mapPick = L.map('pickMap').setView([ANCHOR.lat, ANCHOR.lon], 13);
    osmLayer().addTo(mapPick);
    setTimeout(() => mapPick.invalidateSize(), 100);
    mapPick.on('click', (e) => {
      const [gx, gy] = latLngToGrid(e.latlng.lat, e.latlng.lng);
      state.x = gx; state.y = gy;
      if (!pickDot) pickDot = L.circleMarker(e.latlng, { radius: 9, color: '#0b5fff', fillColor: '#0b5fff', fillOpacity: 1 }).addTo(mapPick);
      else pickDot.setLatLng(e.latlng);
    });
  } else {
    setTimeout(() => mapPick.invalidateSize(), 100);
  }
}
$('pSend').onclick = async () => {
  clearErr();
  $('pConfirm').hidden = true;
  const text = $('pText').value.trim();
  if (!text) return showErr('Décrivez le problème observé.');
  if (text.length > 500) return showErr('Description trop longue (' + text.length + '/500).');
  if (state.x === null) return showErr('Choisissez une position via « Ma position (GPS) » ou « Choisir sur la carte ».');
  try {
    const body = { text, category: $('pCat').value, x: state.x, y: state.y, photoMediaId: state.mediaId };
    if (state.gps) { body.gpsLat = state.gps.lat; body.gpsLon = state.gps.lon; body.gpsAccuracy = state.gps.accuracy; }
    const j = await api('/api/reports', 'POST', body);
    $('pTrackId').textContent = j.id;
    $('pConfirm').hidden = false;
    $('pText').value = ''; $('pCount').textContent = '0';
    state.x = null; state.y = null; state.gps = null;
    $('pCoords').textContent = 'Position : non choisie (grille fictive 5×5 km)';
    $('pRemove').onclick();
    loadRecent(3); drawMap();
  } catch (e) { showErr(e.message); }
};
$('pTrackGo').onclick = () => {
  document.querySelector('.nav-links a[data-nav="suivi"]').click();
  $('tId').value = $('pTrackId').textContent;
  $('tGo').click();
};

// --- Carte publique : fond OpenStreetMap (gratuit, ODbL) + positions
// FICTIVES projetées. La grille 0–5 km n'est PAS une mesure GPS : elle est
// projetée autour d'un point d'ancrage de démonstration, explicitement
// étiqueté comme tel. Ne jamais présenter ces points comme des relevés.
const ANCHOR = { lat: 5.32, lon: -4.02, label: 'Abidjan-Plateau (ancrage fictif de démonstration)' };
const KM_PER_DEG = 111.32;
function gridToLatLng(x, y) {
  return [
    ANCHOR.lat + (y - 2.5) / KM_PER_DEG,
    ANCHOR.lon + (x - 2.5) / (KM_PER_DEG * Math.cos(ANCHOR.lat * Math.PI / 180)),
  ];
}
function latLngToGrid(lat, lon) {
  const x = (lon - ANCHOR.lon) * (KM_PER_DEG * Math.cos(ANCHOR.lat * Math.PI / 180)) + 2.5;
  const y = (lat - ANCHOR.lat) * KM_PER_DEG + 2.5;
  return [Math.min(5, Math.max(0, Math.round(x * 10) / 10)), Math.min(5, Math.max(0, Math.round(y * 10) / 10))];
}
const sevColor = (s) => s === 5 ? '#b3261e' : s === 4 ? '#f97316' : s === 3 ? '#eab308' : (s === 1 || s === 2) ? '#22c55e' : '#94a3b8';
let mapMain = null, layerMain = null;
function osmLayer() {
  return L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
  });
}
async function drawMap() {
  const j = await api('/api/public/incidents');
  if (typeof L === 'undefined') {
    $('pMap').innerHTML = '<p class="map-offline">Fond de carte indisponible (connexion requise pour OpenStreetMap). Les données restent consultables en liste.</p>';
    return;
  }
  if (!mapMain) {
    mapMain = L.map('pMap').setView([ANCHOR.lat, ANCHOR.lon], 13);
    osmLayer().addTo(mapMain);
    layerMain = L.layerGroup().addTo(mapMain);
  }
  layerMain.clearLayers();
  j.incidents.forEach((inc) => {
    const [lat, lon] = gridToLatLng(inc.x, inc.y);
    const label = `${inc.id} — ${inc.domain} — ${inc.reportCount} signalement(s)` +
      (inc.severity === null ? ' — gravité à vérifier' : ' — S' + inc.severity);
    L.circleMarker([lat, lon], { radius: 10, color: sevColor(inc.severity), fillColor: sevColor(inc.severity), fillOpacity: 0.85, weight: 2 })
      .bindPopup(`<b>${esc(inc.id)}</b> (position fictive projetée)<br>${esc(label)}`)
      .bindTooltip(inc.id, { permanent: true, direction: 'right', offset: [8, 0] })
      .addTo(layerMain);
  });
  if (state.x !== null) {
    const ll = state.gps ? [state.gps.lat, state.gps.lon] : gridToLatLng(state.x, state.y);
    const label = state.gps ? 'Votre position GPS (relevé navigateur)' : 'Votre point choisi (grille fictive)';
    L.circleMarker(ll, { radius: 8, color: '#0b5fff', fillColor: '#0b5fff', fillOpacity: 1, weight: 3 })
      .bindPopup(label)
      .addTo(layerMain);
  }
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
    if (r.gps) h += `<p class="muted">Relevé GPS navigateur : ${r.gps.lat.toFixed(5)}, ${r.gps.lon.toFixed(5)}${r.gps.accuracy !== null && r.gps.accuracy !== undefined ? ` (±${Math.round(r.gps.accuracy)} m)` : ''} — fourni par vous, visible uniquement sur cette fiche.</p>`;
    if (isMediaId(r.photo)) h += `<p><a href="/api/photos/${esc(r.photo)}" target="_blank" rel="noopener"><img class="upload preview" style="max-width:220px" src="/api/photos/${esc(r.photo)}" alt="photo du signalement"></a></p>`;
    if (j.incident) h += `<p>Incident associé : <b>${esc(j.incident.id)}</b> (${esc(j.incident.domain)}, ${j.incident.reportCount} signalement(s)).</p>`;
    else h += `<p class="muted">Pas encore rattaché à un incident (regroupement municipal en attente).</p>`;
    h += `<p class="muted">Démonstration : données fictives, aucun délai d'intervention promis.</p></div>`;
    $('tOut').innerHTML = h;
  } catch (e) { $('tErr').textContent = e.message; $('tErr').hidden = false; }
};

(async () => { try { await drawMap(); await loadRecent(3); } catch (e) { console.error(e); } })();
