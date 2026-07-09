/* ============================================================
   MB_Adminjail – NUI v2
   Gleicher Lua-Kontrakt wie zuvor:
   Messages : open, close, setPlayers, setActiveJails, setLogs,
              showJailHud, updateJailHud, hideJailHud
   Callbacks: close, getPlayers, getActiveJails, getLogs,
              jailPlayer, unjailPlayer
   ============================================================ */

'use strict';

const IS_NUI = typeof GetParentResourceName === 'function';
const RESOURCE = IS_NUI ? GetParentResourceName() : 'MB_Adminjail';

const state = {
    players: [],
    activeJails: [],
    logs: [],
    view: 'jail',
    selectedPlayer: null,
    pendingUnjail: null,
    lastTick: 0
};

const els = {};
const $ = (id) => document.getElementById(id);

/* ---------- NUI bridge ---------- */

function post(name, data = {}) {
    if (!IS_NUI) { demoPost(name, data); return Promise.resolve(); }
    return fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).catch(() => null);
}

/* ---------- Utils ---------- */

function escapeHtml(value) {
    return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
}

function formatClock(seconds) {
    seconds = Math.max(0, Math.floor(Number(seconds) || 0));
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    if (h > 0) return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

function formatMinutes(seconds) {
    return `${Math.ceil((Number(seconds) || 0) / 60)} min`;
}

/* ---------- Toasts ---------- */

function toast(message, type = 'info') {
    const icons = { info: 'i-info', success: 'i-check', error: 'i-alert' };
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.innerHTML = `<svg viewBox="0 0 24 24"><use href="#${icons[type] || 'i-info'}"/></svg><span>${escapeHtml(message)}</span>`;
    els.toasts.appendChild(el);
    setTimeout(() => {
        el.classList.add('out');
        setTimeout(() => el.remove(), 220);
    }, 2800);
    while (els.toasts.children.length > 4) els.toasts.firstChild.remove();
}

/* ---------- Theme ---------- */

function applyTheme(theme) {
    const isDark = theme === 'dark';
    document.body.dataset.theme = isDark ? 'dark' : 'light';
    els.themeLabel.textContent = isDark ? 'Light Mode' : 'Dark Mode';
    try { localStorage.setItem('mb_adminjail_theme', theme); } catch (_) {}
}

function loadTheme() {
    let theme = 'dark';
    try { theme = localStorage.getItem('mb_adminjail_theme') || 'dark'; } catch (_) {}
    applyTheme(theme);
}

/* ---------- Clock ---------- */

function updateClock() {
    els.clock.textContent = new Date().toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
}

/* ---------- Navigation ---------- */

const VIEWS = {
    jail:   { title: 'Einjailen',    sub: 'Spieler in das AdminJail versetzen' },
    active: { title: 'Aktive Jails', sub: 'Laufende Strafen verwalten und entlassen' },
    logs:   { title: 'Verlauf',      sub: 'Abgeschlossene und aktive Einträge' }
};

function setView(view) {
    if (!VIEWS[view]) return;
    state.view = view;

    document.querySelectorAll('.nav-item').forEach((b) => b.classList.toggle('active', b.dataset.view === view));
    document.querySelectorAll('.view').forEach((v) => v.classList.toggle('active', v.id === `view-${view}`));

    els.viewTitle.textContent = VIEWS[view].title;
    els.viewSub.textContent = VIEWS[view].sub;

    if (view === 'active') post('getActiveJails');
    if (view === 'logs') { post('getActiveJails'); post('getLogs'); }
}

/* ---------- Spieler-Auswahl (Einjailen) ---------- */

function findPlayerById(value) {
    const raw = String(value || '').trim();
    if (!raw) return null;
    return state.players.find((p) => String(p.source) === raw) || null;
}

function setSelectedPlayer(player) {
    state.selectedPlayer = player || null;

    if (!player) {
        els.playerName.value = '';
        const raw = String(els.playerId.value || '').trim();
        if (raw) {
            els.targetStatus.className = 'pill pill-err';
            els.targetStatus.innerHTML = '<i></i>Nicht gefunden';
        } else {
            els.targetStatus.className = 'pill pill-idle';
            els.targetStatus.innerHTML = '<i></i>Kein Spieler gewählt';
        }
    } else {
        els.playerName.value = player.name || player.serverName || 'Unbekannt';
        els.targetStatus.className = 'pill pill-ok';
        els.targetStatus.innerHTML = '<i></i>Online';
    }

    renderPlayerList();
}

function onPlayerIdInput() {
    setSelectedPlayer(findPlayerById(els.playerId.value));
}

function renderPlayerList() {
    const filter = String(els.playerFilter.value || '').trim().toLowerCase();
    const list = state.players.filter((p) => {
        if (!filter) return true;
        return `${p.source} ${p.name || ''} ${p.serverName || ''}`.toLowerCase().includes(filter);
    });

    els.playerCount.textContent = String(state.players.length);

    if (!list.length) {
        els.playerList.innerHTML = `
            <div class="empty-note">
                <svg viewBox="0 0 24 24"><use href="#i-user"/></svg>
                ${state.players.length ? 'Keine Treffer.' : 'Keine Spieler online.'}
            </div>`;
        return;
    }

    const selectedId = state.selectedPlayer ? String(state.selectedPlayer.source) : null;

    els.playerList.innerHTML = list.map((p) => `
        <button class="player-row${String(p.source) === selectedId ? ' selected' : ''}" data-source="${escapeHtml(p.source)}" type="button" role="option">
            <span class="player-avatar">${escapeHtml(p.source)}</span>
            <span class="player-info">
                <b>${escapeHtml(p.name || 'Unbekannt')}</b>
                <small>Server-ID ${escapeHtml(p.source)}</small>
            </span>
        </button>
    `).join('');

    els.playerList.querySelectorAll('.player-row').forEach((row) => {
        row.addEventListener('click', () => {
            els.playerId.value = row.dataset.source;
            onPlayerIdInput();
        });
    });
}

/* ---------- Jail-Formular ---------- */

function setMinutes(minutes) {
    els.jailMinutes.value = String(minutes);
    syncChips();
}

function syncChips() {
    const current = Number(els.jailMinutes.value);
    document.querySelectorAll('#timeChips .chip').forEach((chip) => {
        chip.classList.toggle('active', Number(chip.dataset.minutes) === current);
    });
}

function updateReasonCount() {
    els.reasonCount.textContent = `${els.jailReason.value.length} / 250`;
}

function submitJail() {
    const player = state.selectedPlayer;
    const minutes = Math.floor(Number(els.jailMinutes.value));
    const reason = String(els.jailReason.value || '').trim();

    if (!player || !player.source) {
        toast('Bitte gib eine gültige Spieler-ID ein.', 'error');
        els.playerId.focus();
        return;
    }
    if (!minutes || minutes < 1 || minutes > 1440) {
        toast('Bitte gib eine gültige Jail-Zeit ein (1–1440 min).', 'error');
        els.jailMinutes.focus();
        return;
    }
    if (!reason) {
        toast('Der Grund ist ein Pflichtfeld.', 'error');
        els.jailReason.focus();
        return;
    }

    post('jailPlayer', { playerId: Number(player.source), minutes, reason });
    toast(`Strafe für ${player.name || 'Spieler'} wurde gesendet.`, 'success');

    els.jailReason.value = '';
    updateReasonCount();
    setTimeout(() => post('getActiveJails'), 800);
}

/* ---------- Aktive Jails ---------- */

function statusPill(record) {
    if (record.status === 'released') return '<span class="pill pill-idle"><i></i>Entlassen</span>';
    if (record.status === 'replaced') return '<span class="pill pill-warn"><i></i>Ersetzt</span>';
    return '<span class="pill pill-ok"><i></i>Aktiv</span>';
}

function recordCard(record) {
    const online = record.online && record.source
        ? `<span class="mono">ID ${escapeHtml(record.source)}</span>`
        : '<span>Offline</span>';

    return `
        <article class="record-card">
            <div class="record-main">
                <div class="record-title">
                    <b>${escapeHtml(record.name || 'Unbekannt')}</b>
                    ${statusPill(record)}
                </div>
                <div class="record-meta">
                    ${online}
                    <span><svg viewBox="0 0 24 24"><use href="#i-shield"/></svg>${escapeHtml(record.jailed_by || 'Unbekannt')}</span>
                    ${record.jailed_at ? `<span><svg viewBox="0 0 24 24"><use href="#i-clock"/></svg>${escapeHtml(record.jailed_at)}</span>` : ''}
                </div>
                <p class="record-reason">${escapeHtml(record.reason || 'Kein Grund gespeichert')}</p>
            </div>
            <div class="record-side">
                <div class="record-timer">
                    <b data-remaining="${escapeHtml(record.id)}">${formatClock(record.time_left)}</b>
                    <small>Restzeit</small>
                </div>
                <button class="btn btn-danger-soft" data-unjail="${escapeHtml(record.id)}" data-name="${escapeHtml(record.name || 'Unbekannt')}" type="button">
                    <svg viewBox="0 0 24 24"><use href="#i-unlock"/></svg>
                    Entjailen
                </button>
            </div>
        </article>
    `;
}

function renderActiveJails() {
    const filter = String(els.activeFilter.value || '').trim().toLowerCase();
    const list = state.activeJails.filter((r) => {
        if (!filter) return true;
        return `${r.name || ''} ${r.reason || ''} ${r.jailed_by || ''}`.toLowerCase().includes(filter);
    });

    const total = state.activeJails.length;
    els.activeMeta.textContent = total === 1 ? '1 aktiver Jail' : `${total} aktive Jails`;
    els.navActiveCount.textContent = String(total);
    els.navActiveCount.classList.toggle('hidden', total === 0);

    if (!list.length) {
        els.activeList.innerHTML = `
            <div class="empty-note">
                <svg viewBox="0 0 24 24"><use href="#i-check"/></svg>
                ${total ? 'Keine Treffer.' : 'Aktuell befindet sich niemand im AdminJail.'}
            </div>`;
        return;
    }

    els.activeList.innerHTML = list.map(recordCard).join('');

    els.activeList.querySelectorAll('[data-unjail]').forEach((button) => {
        button.addEventListener('click', () => openUnjailModal(Number(button.dataset.unjail), button.dataset.name));
    });
}

/* Restzeit sekündlich lokal runterzählen (ohne Re-Render) */
function tickTimers() {
    let changed = false;
    state.activeJails.forEach((record) => {
        if (record.status === 'active' && record.time_left > 0) {
            record.time_left -= 1;
            changed = true;
        }
    });
    if (!changed) return;
    document.querySelectorAll('[data-remaining]').forEach((el) => {
        const record = state.activeJails.find((r) => String(r.id) === el.dataset.remaining);
        if (record) el.textContent = formatClock(record.time_left);
    });
}

/* ---------- Unjail-Modal ---------- */

function openUnjailModal(rowId, name) {
    if (!rowId) return;
    state.pendingUnjail = rowId;
    els.modalText.textContent = `${name || 'Der Spieler'} wird sofort aus dem AdminJail entlassen.`;
    els.modal.classList.add('show');
    els.modal.setAttribute('aria-hidden', 'false');
}

function closeModal() {
    state.pendingUnjail = null;
    els.modal.classList.remove('show');
    els.modal.setAttribute('aria-hidden', 'true');
}

function confirmUnjail() {
    const rowId = state.pendingUnjail;
    closeModal();
    if (!rowId) return;
    post('unjailPlayer', { rowId });
    toast('Entlassung wurde gesendet.', 'success');
    setTimeout(() => post('getActiveJails'), 600);
}

/* ---------- Verlauf ---------- */

function logCard(record) {
    const released = record.status !== 'active';
    return `
        <article class="record-card">
            <div class="record-main">
                <div class="record-title">
                    <b>${escapeHtml(record.name || 'Unbekannt')}</b>
                    ${statusPill(record)}
                </div>
                <div class="record-meta">
                    <span><svg viewBox="0 0 24 24"><use href="#i-clock"/></svg>${escapeHtml(formatMinutes(record.time_left))}</span>
                    <span><svg viewBox="0 0 24 24"><use href="#i-shield"/></svg>${escapeHtml(record.jailed_by || 'Unbekannt')}</span>
                    ${record.jailed_at ? `<span>${escapeHtml(record.jailed_at)}</span>` : ''}
                    ${released && record.released_by ? `<span>Entlassen von ${escapeHtml(record.released_by)}</span>` : ''}
                    ${released && record.released_at ? `<span>${escapeHtml(record.released_at)}</span>` : ''}
                </div>
                <p class="record-reason">${escapeHtml(record.reason || 'Kein Grund gespeichert')}</p>
            </div>
        </article>
    `;
}

function renderLogs() {
    const filter = String(els.logsFilter.value || '').trim().toLowerCase();
    const list = state.logs.filter((r) => {
        if (!filter) return true;
        return `${r.name || ''} ${r.reason || ''} ${r.jailed_by || ''} ${r.released_by || ''}`.toLowerCase().includes(filter);
    });

    els.logsMeta.textContent = state.logs.length === 1 ? '1 Eintrag' : `${state.logs.length} Einträge`;

    if (!list.length) {
        els.logsList.innerHTML = `
            <div class="empty-note">
                <svg viewBox="0 0 24 24"><use href="#i-history"/></svg>
                ${state.logs.length ? 'Keine Treffer.' : 'Noch keine Einträge vorhanden.'}
            </div>`;
        return;
    }

    els.logsList.innerHTML = list.map(logCard).join('');
}

/* ---------- HUD ---------- */

function updateHud(data = {}) {
    const timeLeft = Math.max(0, Number(data.timeLeft) || 0);
    const originalTime = Math.max(timeLeft, Number(data.originalTime) || timeLeft || 1);
    const progress = Math.max(0, Math.min(100, (timeLeft / originalTime) * 100));

    els.hudTime.textContent = formatClock(timeLeft);
    els.hudAdmin.textContent = String(data.jailedBy || 'Unbekannt').slice(0, 18);
    els.hudReason.textContent = String(data.reason || 'Kein Grund').slice(0, 18);
    els.hudProgress.style.width = `${progress}%`;
}

function setHudBackground(transparent) {
    const value = transparent ? 'transparent' : '';
    document.documentElement.style.background = value;
    document.documentElement.style.backgroundColor = value;
    document.body.style.background = value;
    document.body.style.backgroundColor = value;
}

function showHud(data) {
    updateHud(data);
    setHudBackground(true);
    document.documentElement.classList.add('hud-visible');
    document.body.classList.remove('visible');
    document.body.classList.add('hud-visible');
    els.hud.setAttribute('aria-hidden', 'false');
}

function hideHud() {
    document.documentElement.classList.remove('hud-visible');
    document.body.classList.remove('hud-visible');
    setHudBackground(true);
    els.hud.setAttribute('aria-hidden', 'true');
}

/* ---------- Öffnen / Schließen ---------- */

function openTablet() {
    document.body.classList.remove('hud-visible');
    document.body.classList.add('visible');
    els.app.setAttribute('aria-hidden', 'false');
    refreshAll(false);
}

function closeTablet() {
    document.body.classList.remove('visible');
    els.app.setAttribute('aria-hidden', 'true');
    closeModal();
    post('close');
}

function refreshAll(withToast = true) {
    post('getPlayers');
    post('getActiveJails');
    post('getLogs');
    if (withToast) toast('Daten werden aktualisiert ...', 'info');
}

/* ---------- Events ---------- */

function bindEvents() {
    document.querySelectorAll('.nav-item').forEach((button) => {
        button.addEventListener('click', () => setView(button.dataset.view));
    });

    els.closeBtn.addEventListener('click', closeTablet);
    els.refreshBtn.addEventListener('click', () => refreshAll(true));
    els.themeToggle.addEventListener('click', () => {
        applyTheme(document.body.dataset.theme === 'dark' ? 'light' : 'dark');
    });

    els.playerId.addEventListener('input', onPlayerIdInput);
    els.playerFilter.addEventListener('input', renderPlayerList);
    els.jailMinutes.addEventListener('input', syncChips);
    els.jailReason.addEventListener('input', updateReasonCount);
    els.submitJail.addEventListener('click', submitJail);

    document.querySelectorAll('#timeChips .chip').forEach((chip) => {
        chip.addEventListener('click', () => setMinutes(Number(chip.dataset.minutes)));
    });

    els.activeFilter.addEventListener('input', renderActiveJails);
    els.logsFilter.addEventListener('input', renderLogs);

    els.modalCancel.addEventListener('click', closeModal);
    els.modalConfirm.addEventListener('click', confirmUnjail);
    els.modal.addEventListener('click', (event) => {
        if (event.target === els.modal) closeModal();
    });

    document.addEventListener('keydown', (event) => {
        if (event.key !== 'Escape') return;
        if (els.modal.classList.contains('show')) { closeModal(); return; }
        if (document.body.classList.contains('visible')) closeTablet();
    });
}

/* ---------- NUI messages ---------- */

window.addEventListener('message', (event) => {
    const data = event.data || {};

    switch (data.action) {
        case 'open': openTablet(); break;
        case 'close':
            document.body.classList.remove('visible');
            els.app.setAttribute('aria-hidden', 'true');
            closeModal();
            break;
        case 'setPlayers':
            state.players = Array.isArray(data.players) ? data.players : [];
            renderPlayerList();
            onPlayerIdInput();
            break;
        case 'setActiveJails':
            state.activeJails = Array.isArray(data.activeJails) ? data.activeJails : [];
            renderActiveJails();
            break;
        case 'setLogs':
            state.logs = Array.isArray(data.logs) ? data.logs : [];
            renderLogs();
            break;
        case 'showJailHud': showHud(data); break;
        case 'updateJailHud': updateHud(data); break;
        case 'hideJailHud': hideHud(); break;
    }
});

/* ---------- Demo-Modus (nur im Browser, nicht in FiveM) ---------- */

function demoPost(name) {
    if (name === 'getPlayers') {
        window.postMessage({ action: 'setPlayers', players: [
            { source: 1, name: 'Justin Bergmann' },
            { source: 4, name: 'Lea Winkler' },
            { source: 7, name: 'Marco Steiner' },
            { source: 12, name: 'Toni Krause' },
            { source: 23, name: 'Sarah Vogt' },
            { source: 31, name: 'Kevin Roth' }
        ] });
    }
    if (name === 'getActiveJails') {
        window.postMessage({ action: 'setActiveJails', activeJails: [
            { id: 41, name: 'Marco Steiner', reason: 'RDM am Legion Square, mehrfach nach Verwarnung weitergemacht.', time_left: 1560, jailed_by: 'Admin Max', jailed_at: '05.07.2026 14:32:11', status: 'active', online: true, source: 7 },
            { id: 42, name: 'Toni Krause', reason: 'Combat-Logging während einer laufenden Polizeikontrolle.', time_left: 5340, jailed_by: 'Admin Lisa', jailed_at: '05.07.2026 13:58:47', status: 'active', online: true, source: 12 },
            { id: 43, name: 'Dennis Albrecht', reason: 'Metagaming im Support-Fall #2231.', time_left: 620, jailed_by: 'Admin Max', jailed_at: '05.07.2026 15:04:03', status: 'active', online: false, source: null }
        ] });
    }
    if (name === 'getLogs') {
        window.postMessage({ action: 'setLogs', logs: [
            { id: 40, name: 'Kevin Roth', reason: 'Fail-RP bei einem Raub.', time_left: 0, jailed_by: 'Admin Lisa', jailed_at: '05.07.2026 11:20:36', released_by: 'Admin Lisa', released_at: '05.07.2026 12:20:36', status: 'released' },
            { id: 39, name: 'Sarah Vogt', reason: 'Beleidigung im OOC-Chat.', time_left: 0, jailed_by: 'Admin Max', jailed_at: '04.07.2026 21:44:10', released_by: 'SYSTEM', released_at: '04.07.2026 22:14:10', status: 'released' },
            { id: 38, name: 'Marco Steiner', reason: 'VDM auf dem Parkplatz vom Krankenhaus.', time_left: 0, jailed_by: 'Admin Tom', jailed_at: '03.07.2026 19:02:55', released_by: 'Admin Tom', released_at: '03.07.2026 19:47:12', status: 'released' }
        ] });
    }
}

/* ---------- Init ---------- */

document.addEventListener('DOMContentLoaded', () => {
    [
        'app', 'toasts', 'clock', 'themeToggle', 'themeLabel', 'closeBtn', 'refreshBtn',
        'viewTitle', 'viewSub', 'navActiveCount',
        'playerId', 'playerName', 'targetStatus', 'jailMinutes', 'jailReason', 'reasonCount', 'submitJail',
        'playerFilter', 'playerList', 'playerCount',
        'activeFilter', 'activeList', 'activeMeta',
        'logsFilter', 'logsList', 'logsMeta',
        'modal', 'modalText', 'modalCancel', 'modalConfirm',
        'hud', 'hudTime', 'hudAdmin', 'hudReason', 'hudProgress'
    ].forEach((id) => { els[id] = $(id); });

    loadTheme();
    bindEvents();
    updateClock();
    updateReasonCount();
    syncChips();
    setInterval(updateClock, 30000);
    setInterval(tickTimers, 1000);
    setView('jail');
    renderPlayerList();
    renderActiveJails();
    renderLogs();

    if (!IS_NUI) {
        // Browser-Vorschau: Tablet mit Demo-Daten öffnen
        document.body.style.background = '#31445c';
        openTablet();
    }
});
