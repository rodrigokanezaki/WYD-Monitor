/* WYD Monitor desktop view. CSS and page shells are the approved preview assets.
   All game data comes from the local host; this module performs no network requests. */
(() => {
  'use strict';
  const roots = { Work: document.getElementById('wyd-work'), Gamer: document.getElementById('wyd-gamer') };
  const state = { mode: 'Gamer', view: 'overview', pc: 'all', search: '', itemSearch: '', itemPc: 'all', selected: null, appearance: 'dark', density: 'normal', showAbout: false };
  let snapshot = { Characters: [], Items: [], LocalAvailable: true, RemoteAvailable: false, PeerConfigured: false, SoundEnabled: true };
  let received = false, itemSearchTimer = null, revision = 0;
  const peerDraft = { address: '', key: '', showKey: false, edited: false };
  let eventDraft = null, pendingEventSave = null;
  const errors = new Map();
  const alertKinds = [['monitor', 'Monitorar'], ['noItems', 'Sem drop'], ['noXP', 'Sem XP'], ['noFairy', 'Sem fada'], ['printDeath', 'Print ao morrer'], ['noBuff', 'Sem buff XP']];
  const commands = { monitor: 'monitor', noItems: 'drop', noXP: 'xp', noFairy: 'fairy', printDeath: 'death', noBuff: 'buff' };
  const fields = { monitor: 'Monitor', noItems: 'DropAlert', noXP: 'XPAlert', noFairy: 'FairyAlert', printDeath: 'DeathCapture', noBuff: 'BuffAlert' };
  const titles = {
    Work: { overview: ['Visão geral', 'Seus personagens, em um só lugar.'], characters: ['Personagens', 'Cada conta com seu computador de origem.'], items: ['Itens', 'Encontre o que precisa, sem abrir cada inventário.'], alerts: ['Alertas', 'Acompanhe o que precisa da sua atenção.'], events: ['Eventos', 'Sua agenda no horário de Brasília.'], connections: ['Conexões', 'Dois computadores. Uma visão conjunta.'], settings: ['Aparência', 'Seu monitor, do seu jeito.'] },
    Gamer: { overview: ['Sua party, em um só lugar.', 'Cada personagem. Cada recurso. Tudo sob controle.'], characters: ['Seus personagens', 'Status, recursos e avisos na mesma tela.'], items: ['Itens', 'Encontre o que precisa, sem abrir cada inventário.'], alerts: ['Central de alertas', 'Seus avisos, no momento certo.'], events: ['Agenda de eventos', 'Prepare sua próxima partida. Horário de Brasília.'], connections: ['Seus computadores', 'Dois computadores. Uma visão conjunta.'], settings: ['Aparência', 'Seu monitor, do seu jeito.'] }
  };
  const text = value => String(value == null ? '' : value).replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  const field = (record, name, fallback = null) => record && record[name] != null ? record[name] : record && record[name[0].toLowerCase() + name.slice(1)] != null ? record[name[0].toLowerCase() + name.slice(1)] : fallback;
  const num = value => Number.isFinite(Number(value)) ? Number(value) : 0;
  const fmt = value => new Intl.NumberFormat('pt-BR').format(num(value));
  const amount = value => num(value) >= 1e9 ? new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 3 }).format(num(value) / 1e9) + ' bi' : num(value) >= 1e6 ? new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 2 }).format(num(value) / 1e6) + ' mi' : fmt(value);
  const normalize = value => String(value == null ? '' : value).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('pt-BR').trim().replace(/\s+/g, ' ');
  const token = value => Array.from(String(value)).map(ch => ch.codePointAt(0).toString(16)).join('-');
  const icon = name => `<i data-lucide="${name}" aria-hidden="true"></i>`;
  const root = () => roots[state.mode];
  const prefix = () => state.mode === 'Work' ? 'w' : 'g';
  const ids = () => state.mode === 'Work' ? 'ww' : 'gg';
  const get = suffix => root().querySelector('#' + ids() + '-' + suffix);
  function send(command, key = null, value = null, enabled = false, minutes = 0) {
    const message = { command, key, value, enabled: !!enabled, minutes: Math.max(0, Math.min(1440, Math.trunc(num(minutes)))) };
    if (window.chrome && window.chrome.webview) window.chrome.webview.postMessage(message);
  }
  function people() {
    const data = field(snapshot, 'Characters', []);
    return (Array.isArray(data) ? data : []).filter(p => field(p, 'Key')).map(p => ({
      raw: p, id: String(field(p, 'Key')), name: String(field(p, 'Name', 'Personagem')), pc: field(p, 'IsRemote', false) ? 2 : 1,
      origin: String(field(p, 'Origin', field(p, 'IsRemote', false) ? 'Outro PC' : 'Este PC')), remote: !!field(p, 'IsRemote', false),
      hostId: String(field(p, 'HostId', '')), level: field(p, 'Level', '—'), server: String(field(p, 'Server', '—')), map: String(field(p, 'Map', '—')),
      online: !!field(p, 'Online', false), status: String(field(p, 'Status', field(p, 'Online', false) ? 'Online' : 'Offline')),
      activeAlerts: String(field(p, 'ActiveAlerts', '')), detail: String(field(p, 'Detail', '')), hpKnown: !!field(p, 'HPKnown', false), hp: Math.max(0, Math.min(100, num(field(p, 'HPPercent', 0)))),
      fairy: String(field(p, 'Fairy', 'Não confirmado')), xp: String(field(p, 'XP', 'Não confirmado')),
      gold: num(field(p, 'Cash', 0)), coins: num(field(p, 'Coins', 0)), wealth: num(field(p, 'Wealth', 0)),
      cashPartial: !!field(p, 'CashPartial', true), coinsPartial: !!field(p, 'CoinsPartial', true), wealthPartial: !!field(p, 'WealthPartial', true)
    }));
  }
  const available = p => p.remote ? !!field(snapshot, 'RemoteAvailable', false) : !!field(snapshot, 'LocalAvailable', true);
  const visible = () => people().filter(p => available(p) && (state.pc === 'all' || p.pc === Number(state.pc)));
  const selectedRows = () => visible().filter(p => normalize(p.name + ' ' + p.server + ' ' + p.map + ' ' + p.origin).includes(normalize(state.search)));
  const alertPeople = () => people().filter(available);
  const partial = () => (!!field(snapshot, 'PeerConfigured', false) && !field(snapshot, 'RemoteAvailable', false) && state.pc !== '1') || (!field(snapshot, 'LocalAvailable', true) && state.pc !== '2');
  const policy = p => ({ monitor: !!field(p.raw, 'Monitor', false), noItems: !!field(p.raw, 'DropAlert', false), noXP: !!field(p.raw, 'XPAlert', false), noFairy: !!field(p.raw, 'FairyAlert', false), printDeath: !!field(p.raw, 'DeathCapture', false), noBuff: !!field(p.raw, 'BuffAlert', false), noItemsMinutes: Math.max(0, Math.min(1440, num(field(p.raw, 'DropMinutes', 0)))), noXPMinutes: Math.max(0, Math.min(1440, num(field(p.raw, 'XPMinutes', 0)))) });
  const findPerson = key => people().find(p => p.id === key);
  const remoteName = () => (people().find(p => p.remote) || {}).origin || 'Outro PC';
  const localName = () => (people().find(p => !p.remote) || {}).origin || 'Este PC';
  const pcOptions = () => `<option value="all">Todos os PCs</option><option value="1">PC 1 · ${text(localName())}</option><option value="2">PC 2 · ${text(remoteName())}</option>`;

  // Reconcile keyed DOM nodes instead of replacing the page on each polling snapshot.
  // In-progress numeric edits, focus, selection and scroll positions remain untouched.
  function nodeKey(node) {
    if (node.nodeType !== 1) return '';
    if (node.id) return 'id:' + node.id;
    const d = node.dataset;
    if (d.rowKey) return 'row:' + d.rowKey;
    if (d.card) return 'card:' + d.card;
    if (d.character && (d.alert || d.idle)) return 'input:' + d.character + ':' + (d.alert || d.idle) + ':' + (d.idle ? 'minutes' : 'flag');
    if (d.view) return 'view:' + d.view;
    if (d.person) return 'person:' + d.person;
    if (d.action) return 'action:' + d.action;
    return '';
  }
  function compatible(a, b) { return a && b && a.nodeType === b.nodeType && (a.nodeType !== 1 || a.tagName === b.tagName) && (!nodeKey(a) && !nodeKey(b) || nodeKey(a) === nodeKey(b)); }
  function patchNode(oldNode, nextNode) {
    if (oldNode.nodeType === 3) { if (oldNode.nodeValue !== nextNode.nodeValue) oldNode.nodeValue = nextNode.nodeValue; return; }
    if (oldNode.nodeType !== 1) return;
    // These live regions are populated by their dedicated renderers below. The page
    // skeleton must not clear an expanded editor before those renderers run.
    if (/^(ww|gg)-(rows|detail|item-rows)$/.test(oldNode.id) && !nextNode.childNodes.length) return;
    const focused = oldNode === document.activeElement;
    for (const attr of Array.from(oldNode.attributes)) if (!nextNode.hasAttribute(attr.name) && !(focused && attr.name === 'aria-invalid')) oldNode.removeAttribute(attr.name);
    for (const attr of Array.from(nextNode.attributes)) {
      if (focused && attr.name === 'value') continue;
      if (oldNode.getAttribute(attr.name) !== attr.value) oldNode.setAttribute(attr.name, attr.value);
    }
    if (oldNode instanceof HTMLInputElement) {
      if (!focused && oldNode.value !== nextNode.value) oldNode.value = nextNode.value;
      oldNode.checked = nextNode.checked;
      if (!focused) oldNode.setCustomValidity(nextNode.getAttribute('aria-invalid') ? 'Use 0 a 1440 min inteiros.' : '');
      return;
    }
    patchChildren(oldNode, nextNode);
    if (oldNode instanceof HTMLSelectElement && !focused) oldNode.value = nextNode.value;
  }
  function patchChildren(parent, desired) {
    const before = Array.from(parent.childNodes), keyed = new Map(before.filter(n => nodeKey(n)).map(n => [nodeKey(n), n])), used = new Set();
    let cursor = parent.firstChild;
    for (const next of Array.from(desired.childNodes)) {
      const key = nodeKey(next);
      let current = key ? keyed.get(key) : cursor;
      if (!compatible(current, next) || used.has(current)) current = null;
      if (!current) { current = next.cloneNode(true); parent.insertBefore(current, cursor); }
      else { if (current !== cursor) parent.insertBefore(current, cursor); patchNode(current, next); }
      used.add(current); cursor = current.nextSibling;
    }
    for (const old of before) if (!used.has(old) && old.parentNode === parent) old.remove();
  }
  function setHTML(element, html) {
    if (!element) return;
    const template = document.createElement('template'); template.innerHTML = html;
    template.content.querySelectorAll('.w-table-wrap,.g-table-wrap').forEach(element => {
      const c = element.classList.contains('w-table-wrap') ? 'w' : 'g';
      const hint = document.createElement('p'); hint.className = c + '-scroll-hint'; hint.textContent = 'Deslize a tabela para ver mais dados →'; element.before(hint);
    });
    patchChildren(element, template.content);
  }
  function checkbox(p, kind, label = false) {
    const c = prefix(), prefs = policy(p), disabled = p.remote || kind !== 'monitor' && !prefs.monitor;
    return `<label class="${label ? c + '-check' : 'cursor-interaction'}"${p.remote ? ' title="Configure os avisos no computador de origem."' : ''}><input type="checkbox" data-alert="${kind}" data-character="${text(p.id)}" aria-label="${alertKinds.find(k => k[0] === kind)[1]}: ${text(p.name)}, ${text(p.origin)}"${prefs[kind] ? ' checked' : ''}${disabled ? ' disabled' : ''}>${label ? alertKinds.find(k => k[0] === kind)[1] : ''}</label>`;
  }
  function alertControl(p, kind, label = false) {
    if (kind !== 'noItems' && kind !== 'noXP') return checkbox(p, kind, label);
    const c = prefix(), id = ids(), caption = alertKinds.find(k => k[0] === kind)[1], errorId = `${id}-${label ? 'detail' : 'grid'}-${token(p.id)}-${kind}-error`, prefs = policy(p);
    const error = errors.get(p.id + ':' + kind) || '';
    return `<div class="${c}-idle-edit">${label ? `<span class="${c}-idle-label">${caption} por</span>` : ''}<div class="${c}-idle-row">${checkbox(p, kind)}<label class="${c}-minutes"><input class="${c}-control" type="number" inputmode="numeric" min="0" max="1440" step="1" data-idle="${kind}" data-character="${text(p.id)}" aria-label="Tempo ${caption.toLowerCase()} de ${text(p.name)}, ${text(p.origin)}, em minutos" aria-describedby="${errorId}" value="${prefs[kind + 'Minutes']}"${p.remote || !prefs.monitor || !prefs[kind] ? ' disabled' : ''}${error ? ' aria-invalid="true"' : ''}><span>min</span></label></div><span class="${c}-time-error" id="${errorId}" role="alert">${text(error)}</span></div>`;
  }
  function toolbar() {
    const c = prefix(), id = ids();
    return `<div class="${c}-bar"><h2>${state.view === 'characters' ? 'Lista de personagens' : 'Personagens'} <small id="${id}-count"></small></h2><div class="${c}-controls"><select class="${c}-control" id="${id}-pc" aria-label="Filtrar computador">${pcOptions()}</select><label class="${c}-search">${icon('search')}<input class="${c}-control" id="${id}-search" type="search" aria-label="Buscar personagem" placeholder="Buscar personagem" maxlength="80" value="${text(state.search)}"></label></div></div>`;
  }
  function stats() {
    const c = prefix(), id = ids();
    return `<div class="${c}-stats" aria-live="polite"><div class="${c}-stat"><div class="${c}-stat-label">Personagens online</div><div class="${c}-stat-value ${c}-num" id="${id}-online"></div><small id="${id}-scope"></small></div><div class="${c}-stat"><div class="${c}-stat-label">Gold disponível</div><div class="${c}-stat-value ${c}-num" id="${id}-gold"></div><small id="${id}-gold-note"></small></div><div class="${c}-stat"><div class="${c}-stat-label">Moedas de 1kk</div><div class="${c}-stat-value ${c}-num" id="${id}-coins"></div><small id="${id}-coins-note"></small></div><div class="${c}-stat"><div class="${c}-stat-label">Patrimônio total</div><div class="${c}-stat-value ${c}-num" id="${id}-wealth"></div><small id="${id}-wealth-note">Gold + moedas convertidas</small></div></div>`;
  }
  function table() {
    const c = prefix(), id = ids();
    if (state.mode === 'Gamer') return `<div class="g-bar"><label class="g-check"><input type="checkbox" data-monitor-all>Monitorar todos os exibidos</label><button class="g-text-button" data-action="alerts">Central de alertas ${icon('sliders-horizontal')}</button></div><div class="g-party-grid" id="gg-rows" aria-label="Personagens dos computadores"></div><div class="g-table-note"><span id="gg-note"></span><span>Gold e moedas: mochila + baú</span></div>`;
    return `<div class="${c}-bar"><label class="${c}-check"><input type="checkbox" data-monitor-all>Monitorar todos os exibidos</label><button class="${c}-text-button" data-action="alerts">Configurar avisos ${icon('sliders-horizontal')}</button></div><div class="${c}-table-wrap"><table aria-label="Personagens dos computadores"><thead><tr><th class="${c}-check-cell">Avisos</th><th>Personagem</th><th>Origem</th><th>HP</th><th>Fada</th><th>XP</th><th class="${c}-end">Gold</th><th class="${c}-end">1kk</th></tr></thead><tbody id="${id}-rows"></tbody></table></div><div class="${c}-table-note"><span id="${id}-note"></span><span>Gold de mochila + baú</span></div><section id="${id}-detail" hidden></section>`;
  }
  function characterActions(p) {
    const c = prefix();
    if (p.remote) return `<p class="${c}-time-hint">Configure os avisos no computador de origem: ${text(p.origin)}.</p>`;
    return `<div class="${c}-alert-options"><button class="${c}-text-button" data-command="inventory" data-character="${text(p.id)}">Consultar itens deste personagem ${icon('package')}</button></div>`;
  }
  function warning(p) {
    return p.online && p.activeAlerts ? `<div data-active-warning class="${prefix()}-time-hint" style="color:var(--${prefix()}-warn);white-space:normal" role="status">${text(p.activeAlerts)}</div>` : '';
  }
  function activeAlertsPanel() {
    const c = prefix(), active = alertPeople().filter(p => p.online && p.activeAlerts);
    return `<section data-active-alerts class="${c}-settings-list" style="margin-bottom:20px"><div class="${c}-setting"><div><h2>Alertas ativos · ${active.length}</h2>${active.length ? active.map(p => `<p>${text(p.name)} · ${text(p.server)} · PC ${p.pc}: ${text(p.activeAlerts)}</p>`).join('') : '<p>Nenhum alerta ativo.</p>'}</div></div></section>`;
  }
  function serverRows(rows, render) {
    const groups = new Map();
    rows.forEach(p => { const server = p.server && p.server !== '-' ? p.server : 'Servidor não identificado'; if (!groups.has(server)) groups.set(server, []); groups.get(server).push(p); });
    return Array.from(groups.keys()).sort((a,b) => a.localeCompare(b, 'pt-BR', {numeric:true})).map(server => {
      const members = groups.get(server), label = `${text(server)} · ${members.length} personagem${members.length === 1 ? '' : 's'}`;
      const heading = state.mode === 'Work' ? `<tr data-server-group="${text(server)}"><th colspan="8" scope="rowgroup">${label}</th></tr>` : `<h2 data-server-group="${text(server)}" style="grid-column:1/-1;margin:12px 0 0">${label}</h2>`;
      return heading + members.map(render).join('');
    }).join('');
  }
  function renderData() {
    const all = visible(), rows = selectedRows(), online = all.filter(p => p.online), gold = online.reduce((sum, p) => sum + p.gold, 0), coins = online.reduce((sum, p) => sum + p.coins, 0), wealth = online.reduce((sum, p) => sum + p.wealth, 0);
    get('online').textContent = String(online.length); get('gold').textContent = amount(gold); get('coins').textContent = fmt(coins); get('wealth').textContent = amount(wealth);
    get('scope').textContent = state.pc === 'all' ? (field(snapshot, 'RemoteAvailable', false) ? 'Em 2 computadores' : 'Somente este PC disponível') : 'No computador selecionado';
    get('gold-note').textContent = partial() || online.some(p => p.cashPartial) ? 'Parcial · leitura incompleta' : 'Mochila + baú';
    get('coins-note').textContent = partial() || online.some(p => p.coinsPartial) ? 'Parcial · leitura incompleta' : 'Mochila + baú';
    get('wealth-note').textContent = partial() || online.some(p => p.wealthPartial) ? 'Parcial · leitura incompleta' : 'Gold + moedas convertidas';
    get('count').textContent = '· ' + rows.length;
    get('note').textContent = rows.length + ' de ' + all.length + ' personagens' + (state.search ? ' · totais do PC filtrado' : '') + ' · somente online na soma';
    if (state.mode === 'Work') {
      setHTML(get('rows'), rows.length ? serverRows(rows, p => `<tr data-row-key="${text(p.id)}"><td class="w-check-cell">${checkbox(p, 'monitor')}</td><td><button class="w-char" data-person="${text(p.id)}">${text(p.name)}</button><span class="w-subline" title="${text(p.detail)}">${p.online ? `Nv. ${text(p.level)} · ${text(p.server)}` : text(p.status)}</span>${warning(p)}</td><td><span class="w-muted" title="${text(p.origin)}">PC ${p.pc}</span></td><td><div class="w-hp w-num" title="${text(p.status)}">${p.hpKnown ? p.hp + '%' : '—'}<div class="w-hp-track"><span style="width:${p.hpKnown ? p.hp : 0}%"></span></div></div></td><td class="w-num ${p.fairy === 'Ausente' ? 'w-warning' : ''}">${text(p.fairy === 'Ausente' ? 'Sem fada' : p.fairy)}</td><td class="w-num">${text(p.xp)}</td><td class="w-end w-num" title="${fmt(p.gold)}${p.cashPartial ? ' · parcial' : ''}">${p.online ? amount(p.gold) + (p.cashPartial ? ' *' : '') : '—'}</td><td class="w-end w-num">${p.online ? fmt(p.coins) + (p.coinsPartial ? ' *' : '') : '—'}</td></tr>`) : `<tr><td colspan="8" class="w-empty">${emptyCharacters()}</td></tr>`);
    } else {
      setHTML(get('rows'), rows.length ? serverRows(rows, p => `<article class="g-party-card" data-card="${text(p.id)}" aria-label="${text(p.name)}, ${text(p.origin)}"><div class="g-party-header"><div class="g-identity"><span class="g-crest" aria-hidden="true">${text(p.name[0] || 'W')}</span><div class="g-player-title"><h3>${text(p.name)}</h3><small>Nível ${text(p.level)} · ${text(p.server)}</small></div><span class="g-origin" title="${text(p.origin)}">PC ${p.pc}</span></div><div class="g-location"><span>${text(p.map)}</span><span class="g-online-status" title="${text(p.detail)}"${p.online ? '' : ' style="color:var(--g-warn)"'}><span class="g-dot"${p.online ? '' : ' style="background:var(--g-warn)"'}></span>${text(p.status)}</span></div></div><div class="g-party-body"><div class="g-vitals-label"><span>HP</span><strong class="g-num">${p.hpKnown ? p.hp + '%' : '—'}</strong></div><div class="g-hp-track"><span style="width:${p.hpKnown ? p.hp : 0}%"></span></div><div class="g-timers"><div class="${p.fairy === 'Ausente' ? 'g-missing' : ''}"><span>Fada</span><strong>${text(p.fairy === 'Ausente' ? 'Sem fada' : p.fairy)}</strong></div><div><span>Buff de XP</span><strong>${text(p.xp)}</strong></div></div><div class="g-money"><div><span>Gold</span><strong class="g-num" title="${fmt(p.gold)}${p.cashPartial ? ' · parcial' : ''}">${p.online ? amount(p.gold) + (p.cashPartial ? ' *' : '') : '—'}</strong></div><div><span>Moedas 1kk</span><strong class="g-num">${p.online ? fmt(p.coins) + (p.coinsPartial ? ' *' : '') : '—'}</strong></div></div></div><div class="g-party-footer"><div class="g-party-actions">${checkbox(p, 'monitor', true)}<button class="g-text-button" data-person="${text(p.id)}" aria-expanded="${state.selected === p.id}" aria-controls="gg-options-${token(p.id)}">Ajustar avisos ${icon('sliders-horizontal')}</button></div>${warning(p)}<div class="g-policy-summary" data-policy-summary="${text(p.id)}">${text(policySummary(p))}</div></div><section class="g-card-options" id="gg-options-${token(p.id)}" data-options="${text(p.id)}"${state.selected === p.id ? '' : ' hidden'}>${state.selected === p.id ? gamerDetail(p) : ''}</section></article>`) : `<div class="g-empty">${emptyCharacters()}</div>`);
    }
    renderDetail(); updateControls();
  }
  function emptyCharacters() { return !received ? 'Aguardando leitura dos personagens…' : state.pc === '2' && !field(snapshot, 'RemoteAvailable', false) ? 'PC 2 sem conexão. Seus dados não entram nos totais.' : 'Nenhum personagem encontrado.'; }
  function policySummary(p) { const prefs = policy(p); return p.remote ? 'Avisos configurados no computador de origem' : !prefs.monitor ? 'Avisos pausados' : `Sem drop: ${prefs.noItems ? prefs.noItemsMinutes + ' min' : 'desligado'} · Sem XP: ${prefs.noXP ? prefs.noXPMinutes + ' min' : 'desligado'}`; }
  function gamerDetail(p) {
    return `<div class="g-bar"><h3>Avisos · ${text(p.name)}</h3><button class="g-text-button" data-action="close-detail">Fechar ${icon('x')}</button></div><div class="g-alert-options">${alertKinds.filter(([kind]) => kind !== 'monitor').map(([kind]) => alertControl(p, kind, true)).join('')}</div><p class="g-time-hint">Tempo em minutos. 0 desliga o aviso.</p><p class="g-time-hint">Gold: ${p.online ? fmt(p.gold) : '—'} · Patrimônio: ${p.online ? fmt(p.wealth) : '—'}</p>${characterActions(p)}`;
  }
  function renderDetail() {
    const p = selectedRows().find(p => p.id === state.selected);
    if (state.mode === 'Work') {
      const box = get('detail'); if (!box) return; box.hidden = !p; if (!p) return;
      box.className = 'w-detail';
      setHTML(box, `<div class="w-bar"><h2>${text(p.name)} <small>· PC ${p.pc}</small></h2><button class="w-text-button" data-action="close-detail">Fechar ${icon('x')}</button></div><div class="w-detail-grid"><div><small>Localização</small><strong>${text(p.map)}</strong></div><div><small>Servidor</small><strong>${text(p.server)}</strong></div><div><small>Gold confirmado</small><strong class="w-num">${p.online ? fmt(p.gold) : '—'}</strong></div><div><small>Patrimônio</small><strong class="w-num">${p.online ? fmt(p.wealth) : '—'}</strong></div></div><div class="w-detail-alerts"><h3>Avisos deste personagem</h3><div class="w-alert-options">${alertKinds.map(([kind]) => alertControl(p, kind, true)).join('')}</div><p class="w-time-hint">Minutos sem ganhar XP ou receber drops (itens). 0 desliga o aviso.</p>${characterActions(p)}</div>`);
    } else {
      root().querySelectorAll('[data-options]').forEach(box => { const selected = box.dataset.options === state.selected; box.hidden = !selected; if (selected && p) setHTML(box, gamerDetail(p)); });
      root().querySelectorAll('[data-person]').forEach(button => button.setAttribute('aria-expanded', String(button.dataset.person === state.selected)));
    }
    updateControls();
  }
  function eventRows() {
    return String(field(snapshot, 'EventText', '')).split(/\r?\n/).filter(Boolean).map(line => { const parts = line.split('|').map(part => part.trim()); const time = parts[1] && parts[1].match(/\b\d{2}:\d{2}\b/); return { name: parts[0], when: parts[1] || '', time: time ? time[0] : '', remaining: parts[2] || '' }; });
  }
  function footerPanels() {
    const c = prefix(), events = eventRows().slice(0, 2), activity = visible().filter(p => p.online && p.activeAlerts).map(p => `${p.name} · ${p.server}: ${p.activeAlerts}`); if (!activity.length) activity.push('Nenhum alerta ativo.');
    return `<div class="${c}-footer-panels"><section><div class="${c}-bar"><h2>Próximos eventos</h2><button class="${c}-text-button" data-action="events">Ver agenda ${icon('arrow-up-right')}</button></div>${events.length ? events.map(event => `<div class="${c}-lineitem"><span class="${c}-time">${text(event.time)}</span><div class="${c}-grow">${text(event.name)}<div class="${c}-description">${text(event.when)}</div></div>${event.remaining ? `<span class="${c}-badge">${text(event.remaining)}</span>` : ''}</div>`).join('') : `<div class="${c}-lineitem"><div class="${c}-muted">Aguardando agenda de eventos.</div></div>`}</section><section><div class="${c}-bar"><h2>Atenção</h2><button class="${c}-text-button" data-action="alerts">Ver alertas ${icon('arrow-up-right')}</button></div>${activity.map(line => `<div class="${c}-lineitem"><span class="${c}-muted">${icon('circle-alert')}</span><div>${text(line)}</div></div>`).join('')}</section></div>`;
  }
  function peerPanel() {
    const c = prefix(), id = ids(), peer = field(snapshot, 'Peer', {}), addresses = field(peer, 'Addresses', []);
    const localCount = people().filter(p => !p.remote && p.online && available(p)).length, remoteCount = people().filter(p => p.remote && p.online && available(p)).length;
    const connected = !!field(peer, 'Connected', field(snapshot, 'RemoteAvailable', false)), active = !!field(peer, 'Active', connected), identity = !!field(peer, 'IdentityAvailable', true);
    return `<h2>Computadores vinculados</h2><div class="${c}-settings-list"><div class="${c}-setting"><div><div class="${c}-setting-title">${icon('monitor')}PC 1 · ${text(field(peer, 'HostName', localName()))}</div><p>Este computador · ${localCount} personagens online</p><p>IP deste PC: ${text(Array.isArray(addresses) && addresses.length ? addresses.join(' · ') : 'Aguardando identificação da rede')}</p></div><span class="${c}-switch"><span class="${c}-dot"></span>${text(field(snapshot, 'LocalStatus', 'Aguardando leitura'))}</span></div><div class="${c}-setting"><div><div class="${c}-setting-title">${icon('monitor')}PC 2 · ${text(remoteName())}</div><p>${remoteCount} personagens online · ${text(field(peer, 'State', field(snapshot, 'RemoteStatus', 'Não configurado')))}</p></div><button class="${c}-action" data-command="peer-disconnect"${active ? '' : ' disabled'}>${icon('wifi-off')}Desconectar</button></div></div><form class="${c}-detail" data-peer-form><div class="${c}-bar"><h3>Conectar os dois computadores</h3><button type="button" class="${c}-text-button" data-command="peer-generate"${identity ? '' : ' disabled'}>Gerar chave ${icon('key-round')}</button></div><p class="${c}-muted" style="margin-top:8px;font-size:13px">Use a mesma chave nos dois PCs. Em cada um, informe o IP do outro computador.</p><div class="${c}-item-filters" style="margin-top:16px"><label class="${c}-item-field" for="${id}-peer-address">IP do outro computador<input class="${c}-control" id="${id}-peer-address" data-peer-field="address" type="text" autocomplete="off" spellcheck="false" placeholder="Ex.: 192.168.1.20" maxlength="253" value="${text(peerDraft.address)}" required></label><label class="${c}-item-field" for="${id}-peer-key">Chave de conexão<input class="${c}-control" id="${id}-peer-key" data-peer-field="key" type="${peerDraft.showKey ? 'text' : 'password'}" autocomplete="off" spellcheck="false" maxlength="512" value="${text(peerDraft.key)}" required></label></div><div class="${c}-bar"><button type="button" class="${c}-text-button" data-action="toggle-peer-key">${peerDraft.showKey ? 'Ocultar' : 'Mostrar'} chave</button><button type="submit" class="${c}-action ${c}-primary"${identity ? '' : ' disabled'}>Conectar computadores ${icon('arrow-right')}</button></div>${identity ? '' : `<p class="${c}-warning">A identidade de rede está indisponível. Verifique o aviso do monitor antes de conectar.</p>`}</form><div class="${c}-detail"><h3>Quando um PC desconectar</h3><p class="${c}-muted" style="margin-top:8px;font-size:13px">Os personagens desse PC saem da soma. Os totais ficam parciais até a conexão voltar.</p><p class="${c}-muted" style="margin-top:8px;font-size:13px">Baús compartilhados podem aparecer em mais de um personagem. Considere essa repetição ao conferir os totais.</p><button class="${c}-text-button" style="margin-top:12px" data-action="overview">Voltar ao painel ${icon('arrow-right')}</button></div>`;
  }
  function eventDefinitions() { const events = field(snapshot, 'Events', []); return Array.isArray(events) ? events : []; }
  function eventMatches(event, expected) {
    if (expected.Id && String(field(event, 'Id', '')) !== expected.Id) return false;
    for (const name of ['Name', 'TimeZone', 'RecurrenceType', 'SpecificDate', 'Notes']) if (String(field(event, name, '')) !== String(expected[name] || '')) return false;
    if (!!field(event, 'Enabled', false) !== expected.Enabled || num(field(event, 'DayOfMonth', 0)) !== num(expected.DayOfMonth)) return false;
    for (const name of ['Times', 'DaysOfWeek', 'ReminderOffsets']) if (JSON.stringify(Array.from(field(event, name, []) || []).map(String).sort()) !== JSON.stringify(Array.from(expected[name] || []).map(String).sort())) return false;
    return true;
  }
  function eventFrequency(event) {
    const kind = field(event, 'RecurrenceType', 'DAILY');
    if (kind === 'WEEKLY') return (field(event, 'DaysOfWeek', []) || []).map(day => ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'][day] || '').filter(Boolean).join(' · ');
    if (kind === 'MONTHLY') return 'Todo mês · dia ' + field(event, 'DayOfMonth', '');
    if (kind === 'ONCE') return String(field(event, 'SpecificDate', ''));
    return 'Todos os dias';
  }
  function startEventEditor(event) {
    eventDraft = { Id: String(field(event, 'Id', '')), Name: String(field(event, 'Name', '')), Enabled: !!field(event, 'Enabled', true), TimeZone: String(field(event, 'TimeZone', 'America/Sao_Paulo')), RecurrenceType: String(field(event, 'RecurrenceType', 'DAILY')), Times: (field(event, 'Times', []) || []).join(', '), DaysOfWeek: Array.from(field(event, 'DaysOfWeek', []) || []), DayOfMonth: String(field(event, 'DayOfMonth', 1) || 1), SpecificDate: String(field(event, 'SpecificDate', '')), ReminderOffsets: (field(event, 'ReminderOffsets', [15, 5, 0]) || []).join(', '), Notes: String(field(event, 'Notes', '')) };
    pendingEventSave = null; draw();
  }
  function eventEditor() {
    if (!eventDraft) return '';
    const c = prefix(), id = ids(), draft = eventDraft, writable = !!field(snapshot, 'EventsWritable', true);
    return `<form class="${c}-detail" data-event-editor><div class="${c}-bar"><h3>${draft.Id ? 'Editar evento' : 'Novo evento'}</h3><button type="button" class="${c}-text-button" data-action="cancel-event">Fechar ${icon('x')}</button></div><div class="${c}-item-filters" style="margin-top:16px"><label class="${c}-item-field" for="${id}-event-name">Nome do evento<input class="${c}-control" id="${id}-event-name" data-event-field="Name" value="${text(draft.Name)}" maxlength="80" required></label><label class="${c}-item-field" for="${id}-event-kind">Frequência<select class="${c}-control" id="${id}-event-kind" data-event-field="RecurrenceType">${[['DAILY', 'Todos os dias'], ['WEEKLY', 'Semanal'], ['MONTHLY', 'Mensal'], ['ONCE', 'Uma vez']].map(([value, caption]) => `<option value="${value}"${draft.RecurrenceType === value ? ' selected' : ''}>${caption}</option>`).join('')}</select></label></div>${draft.RecurrenceType === 'WEEKLY' ? `<div class="${c}-alert-options">${['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'].map((caption, day) => `<label class="${c}-check"><input type="checkbox" data-event-day="${day}"${draft.DaysOfWeek.includes(day) ? ' checked' : ''}>${caption}</label>`).join('')}</div>` : ''}${draft.RecurrenceType === 'MONTHLY' ? `<label class="${c}-item-field" style="margin-top:14px">Dia do mês<input class="${c}-control" type="number" min="1" max="31" data-event-field="DayOfMonth" value="${text(draft.DayOfMonth)}" required></label>` : ''}${draft.RecurrenceType === 'ONCE' ? `<label class="${c}-item-field" style="margin-top:14px">Data<input class="${c}-control" type="date" data-event-field="SpecificDate" value="${text(draft.SpecificDate)}" required></label>` : ''}<div class="${c}-item-filters" style="margin-top:16px"><label class="${c}-item-field" for="${id}-event-times">Horários, separados por vírgula<input class="${c}-control" id="${id}-event-times" data-event-field="Times" value="${text(draft.Times)}" placeholder="11:00, 17:00, 22:00" maxlength="200" required></label><label class="${c}-item-field" for="${id}-event-reminders">Avisar antes, em minutos<input class="${c}-control" id="${id}-event-reminders" data-event-field="ReminderOffsets" value="${text(draft.ReminderOffsets)}" placeholder="15, 5, 0" maxlength="120"></label></div><div class="${c}-item-filters"><label class="${c}-item-field" for="${id}-event-notes">Observações<input class="${c}-control" id="${id}-event-notes" data-event-field="Notes" value="${text(draft.Notes)}" maxlength="500" placeholder="Ex.: no TS"></label><label class="${c}-item-field" for="${id}-event-zone">Fuso horário<input class="${c}-control" id="${id}-event-zone" data-event-field="TimeZone" value="${text(draft.TimeZone)}" maxlength="100" required></label></div><div class="${c}-bar"><label class="${c}-check"><input type="checkbox" data-event-field="Enabled"${draft.Enabled ? ' checked' : ''}>Evento ativo</label><div class="${c}-controls">${draft.Id ? `<button type="button" class="${c}-action" data-delete-event="${text(draft.Id)}"${writable ? '' : ' disabled'}>Excluir evento</button>` : ''}<button type="submit" class="${c}-action ${c}-primary"${writable ? '' : ' disabled'}>Salvar evento</button></div></div></form>`;
  }
  function eventsPanel() {
    const c = prefix(), definitions = eventDefinitions(), writable = !!field(snapshot, 'EventsWritable', true);
    return `<div class="${c}-bar"><h2>Agenda de eventos</h2><button class="${c}-text-button" data-action="new-event"${writable ? '' : ' disabled'}>Adicionar evento ${icon('plus')}</button></div>${writable ? '' : `<div class="${c}-banner">A agenda está indisponível para edição. O arquivo foi preservado.</div>`}<div class="${c}-table-wrap"><table><thead><tr><th>Evento</th><th>Frequência</th><th>Horários</th></tr></thead><tbody>${definitions.length ? definitions.map(event => `<tr data-row-key="${text(field(event, 'Id', ''))}"><td><button class="${c}-char" data-edit-event="${text(field(event, 'Id', ''))}">${text(field(event, 'Name', ''))}</button><span class="${c}-subline">${text(field(event, 'Notes', '')) || text(field(event, 'TimeZone', ''))}</span></td><td class="${c}-muted">${text(eventFrequency(event))}</td><td class="${c}-num">${text((field(event, 'Times', []) || []).join(' · '))}<span class="${c}-subline"><label class="${c}-check"><input type="checkbox" data-event-toggle="${text(field(event, 'Id', ''))}"${field(event, 'Enabled', true) ? ' checked' : ''}${writable ? '' : ' disabled'}>Ativo</label></span></td></tr>`).join('') : `<tr><td colspan="3" class="${c}-empty">Nenhum evento cadastrado.</td></tr>`}</tbody></table></div>${eventEditor()}`;
  }
  function renderItems() {
    const c = prefix(), id = ids(), query = normalize(state.itemSearch), data = field(snapshot, 'Items', []);
    const rows = (Array.isArray(data) ? data : []).filter(item => state.itemPc !== '2' && normalize([field(item, 'Item', ''), field(item, 'ItemId', ''), field(item, 'Character', ''), field(item, 'Area', '')].join(' ')).includes(query));
    const body = get('item-rows'); if (!body) return;
    setHTML(body, rows.length ? rows.map((item, index) => `<tr data-row-key="${text(field(item, 'Key', index))}" data-inventory-key="${text(field(item, 'CharacterKey', ''))}" title="ID: ${text(field(item, 'ItemId', ''))} · ${text(field(item, 'Fresh', ''))} · ${text(field(item, 'Time', ''))}${field(item, 'CharacterKey') ? ' · Duplo clique para abrir o inventário' : ''}"><td>${text(field(item, 'Item', ''))}</td><td>${text(field(item, 'Character', ''))}</td><td title="${text(field(item, 'Origin', localName()))}">PC 1</td><td>${text(field(item, 'Area', ''))}</td><td class="${c}-end ${c}-num">${text(field(item, 'Quantity', ''))}</td></tr>`).join('') : `<tr><td colspan="5" class="${c}-empty">${state.itemPc === '2' ? 'Os itens do outro computador ainda não são compartilhados.' : 'Nenhum item encontrado. Tente outro nome, ID ou local.'}</td></tr>`);
    get('item-count').textContent = rows.length + ' ' + (rows.length === 1 ? 'resultado' : 'resultados') + (field(snapshot, 'ItemStatus', '') ? ' · ' + field(snapshot, 'ItemStatus', '') : '');
  }
  function draw() {
    const c = prefix(), id = ids(), active = root();
    for (const [mode, element] of Object.entries(roots)) { if (mode === state.mode) element.removeAttribute('data-inactive'); else element.setAttribute('data-inactive', ''); }
    active.style.colorScheme = state.appearance === 'system' ? 'light dark' : state.appearance;
    active.style.setProperty('--' + c + '-row', state.density === 'compact' ? '9px' : '13px');
    if (c === 'g') active.style.setProperty('--g-card-pad', state.density === 'compact' ? '12px' : '17px');
    document.documentElement.style.colorScheme = active.style.colorScheme;
    get('title').textContent = titles[state.mode][state.view][0]; get('subtitle').textContent = titles[state.mode][state.view][1];
    active.querySelectorAll('[data-view]').forEach(button => { if (button.dataset.view === state.view) button.setAttribute('aria-current', 'page'); else button.removeAttribute('aria-current'); });
    setHTML(get('sources'), `<button class="${c}-source${field(snapshot, 'LocalAvailable', true) ? '' : ' off'}" data-action="connections"><span class="${c}-dot"></span>PC 1 · ${text(localName())} <span class="${c}-muted">${text(field(snapshot, 'LocalStatus', 'Aguardando leitura'))}</span></button><button class="${c}-source${field(snapshot, 'RemoteAvailable', false) ? '' : ' off'}" data-action="connections"><span class="${c}-dot"></span>PC 2 · ${text(remoteName())} <span class="${c}-muted">${text(field(snapshot, 'RemoteStatus', 'Não configurado'))}</span></button>`);
    let html = '';
    if (state.view === 'overview' || state.view === 'characters') {
      html = `${partial() ? `<div class="${c}-banner">${icon('wifi-off')}Leitura incompleta. Os totais não incluem os computadores indisponíveis.</div>` : ''}${stats()}${toolbar()}${table()}${state.view === 'overview' ? footerPanels() : ''}`;
    } else if (state.view === 'connections') {
      html = peerPanel();
    } else if (state.view === 'settings') {
      const modes = state.mode === 'Work' ? ['Work', 'Gamer'] : ['Gamer', 'Work'];
      html = `<h2>Modo de exibição</h2><div class="${c}-settings-list">${modes.map(mode => `<div class="${c}-setting"><div><div class="${c}-setting-title">${icon(mode === 'Work' ? 'briefcase-business' : 'gamepad-2')}Modo ${mode}</div><p>${mode === 'Work' ? 'Azul original, lista compacta e foco nas informações.' : 'Cartões por personagem, azul original e avisos sempre à mão.'}</p></div>${mode === state.mode ? `<span class="${c}-badge">Selecionado</span>` : `<button class="${c}-action" data-mode="${mode}">Usar Modo ${mode}</button>`}</div>`).join('')}<div class="${c}-setting"><div><h3>Cor da interface</h3><p>Ajuste para comparar as duas aparências.</p></div><select id="${id}-appearance" class="${c}-control" aria-label="Cor da interface"><option value="system">Acompanhar sistema</option><option value="light">Clara</option><option value="dark">Escura</option></select></div><div class="${c}-setting"><div><h3>Espaçamento ${c === 'g' ? 'dos cartões' : 'da lista'}</h3><p>Mais respiro ou mais personagens na tela.</p></div><select id="${id}-density" class="${c}-control" aria-label="Espaçamento"><option value="normal">Confortável</option><option value="compact">Compacto</option></select></div></div><div class="${c}-alert-options"><button class="${c}-text-button" data-command="test-alert">Testar aviso</button><button class="${c}-text-button" data-command="clear-alerts">Limpar avisos</button><button class="${c}-text-button" data-command="fullscreen">Tela cheia</button><button class="${c}-text-button" data-command="about">Sobre o WYD Monitor</button></div>`;
    } else if (state.view === 'events') {
      html = eventsPanel();
    } else if (state.view === 'alerts') {
      html = `${activeAlertsPanel()}<div class="${c}-bar"><h2>Avisos por personagem</h2><label class="${c}-check"><input type="checkbox" id="${id}-sound"${field(snapshot, 'SoundEnabled', true) ? ' checked' : ''}>Som nos avisos</label></div><div class="${c}-bar"><label class="${c}-check"><input type="checkbox" data-monitor-all>Monitorar todos</label><small>Avisar após o tempo sem XP ou drop.</small></div><div class="${c}-table-wrap"><table class="${c}-alerts-table" aria-label="Configuração de avisos por personagem"><thead><tr><th>Personagem</th>${alertKinds.map(([, label]) => `<th>${label}</th>`).join('')}</tr></thead><tbody>${alertPeople().map(p => `<tr data-row-key="${text(p.id)}"><td><button class="${c}-char" data-open-person="${text(p.id)}">${text(p.name)}</button><span class="${c}-subline">PC ${p.pc} · ${text(p.server)}</span></td>${alertKinds.map(([kind]) => `<td class="${c}-check-cell">${alertControl(p, kind)}</td>`).join('')}</tr>`).join('') || `<tr><td colspan="7" class="${c}-empty">Nenhum personagem disponível.</td></tr>`}</tbody></table></div><p class="${c}-time-hint">Tempo em minutos por personagem · Sem drop = sem receber itens · 0 desliga o aviso.</p><p class="${c}-muted" style="margin-top:8px;font-size:12px">Os avisos de personagens remotos são configurados no computador de origem.</p><div class="${c}-settings-list"><div class="${c}-setting"><div><div class="${c}-setting-title">${icon('circle-alert')}Atividade recente</div><p style="white-space:pre-line">${text(field(snapshot, 'ActivityText', 'Nenhum aviso nesta sessão.'))}</p></div></div></div>`;
    } else if (state.view === 'items') {
      html = `<div class="${c}-bar"><h2>Consulta de itens</h2><button class="${c}-text-button" data-command="refresh">Atualizar ${icon('refresh-cw')}</button></div><div class="${c}-item-filters"><label class="${c}-item-field" for="${id}-item-search">Buscar item ou personagem<input class="${c}-control" id="${id}-item-search" type="search" maxlength="80" placeholder="Nome do item, ID, personagem ou local" value="${text(state.itemSearch)}"></label><label class="${c}-item-field" for="${id}-item-pc">Computador<select class="${c}-control" id="${id}-item-pc">${pcOptions()}</select></label></div><p class="${c}-item-count" id="${id}-item-count" role="status" aria-live="polite"></p><div class="${c}-table-wrap${c === 'g' ? ' g-items-table' : ''}"><table aria-label="Resultados da consulta de itens"><thead><tr><th>Item</th><th>Personagem</th><th>PC</th><th>Local</th><th class="${c}-end">Qtd.</th></tr></thead><tbody id="${id}-item-rows"></tbody></table></div><p class="${c}-muted" style="margin-top:14px;font-size:12px">Consulta de inventário deste PC. Os itens do outro computador ainda não são compartilhados.</p>`;
    }
    if (state.view === 'settings' && state.showAbout) html += `<div class="${c}-detail"><h3>Sobre o WYD Monitor</h3><p class="${c}-muted" style="margin-top:8px;font-size:13px">Acompanhe seus personagens, recursos, eventos e avisos em um só lugar.</p><p class="${c}-muted" style="margin-top:8px;font-size:13px">O Modo Gamer organiza os personagens em cartões. O Modo Work usa uma lista compacta. Os dois compartilham os mesmos dados e configurações de aviso.</p></div>`;
    setHTML(get('primary'), html);
    if (state.view === 'overview' || state.view === 'characters') { get('pc').value = state.pc; renderData(); }
    if (state.view === 'items') { get('item-pc').value = state.itemPc; renderItems(); }
    if (state.view === 'settings') { get('appearance').value = state.appearance; get('density').value = state.density; }
    active.querySelectorAll('.' + c + '-table-wrap').forEach(element => { if (element.previousElementSibling && element.previousElementSibling.classList.contains(c + '-scroll-hint')) return; const hint = document.createElement('p'); hint.className = c + '-scroll-hint'; hint.textContent = 'Deslize a tabela para ver mais dados →'; element.before(hint); });
    updateControls();
  }
  function updateControls() {
    const scope = (state.view === 'alerts' ? alertPeople() : selectedRows()).filter(p => !p.remote), count = scope.filter(p => policy(p).monitor).length;
    root().querySelectorAll('[data-monitor-all]').forEach(input => { input.checked = scope.length > 0 && count === scope.length; input.indeterminate = count > 0 && count < scope.length; input.disabled = !scope.length; input.title = 'Aplica somente aos personagens deste PC.'; });
    root().querySelectorAll('button,select,input[type=checkbox]').forEach(element => element.classList.add('cursor-interaction'));
    if (globalThis.lucide) globalThis.lucide.createIcons({ attrs: { width: 17, height: 17 } });
  }
  function feedback(message) { const element = get('alert-feedback'); if (element) element.textContent = message; }
  function navigate(view) {
    if (!titles[state.mode][view]) return;
    state.view = view; state.selected = null; draw(); send('navigate', null, view);
  }
  function handleClick(event) {
    const button = event.target.closest('button'); if (!button || !root().contains(button)) return;
    const d = button.dataset;
    if (d.view) { navigate(d.view); return; }
    if (d.mode && roots[d.mode]) { state.mode = d.mode; draw(); send('mode', null, d.mode); return; }
    if (d.editEvent) { const event = eventDefinitions().find(item => String(field(item, 'Id', '')) === d.editEvent); if (event) startEventEditor(event); return; }
    if (d.deleteEvent && field(snapshot, 'EventsWritable', true)) { send('event-delete', d.deleteEvent); eventDraft = null; pendingEventSave = null; draw(); return; }
    if (d.person) { state.selected = state.selected === d.person ? null : d.person; renderDetail(); return; }
    if (d.openPerson) { const p = findPerson(d.openPerson); if (!p) return; state.view = 'characters'; state.pc = String(p.pc); state.search = p.name; state.selected = p.id; draw(); send('navigate', null, state.view); return; }
    if (d.command === 'about') { state.showAbout = !state.showAbout; draw(); return; }
    if (d.command) { const p = d.character ? findPerson(d.character) : null; if (p && p.remote) return; send(d.command, d.character || null, d.command === 'refresh' ? state.itemSearch : null); return; }
    if (d.action === 'close-detail') { state.selected = null; renderDetail(); return; }
    if (d.action === 'toggle-peer-key') { peerDraft.showKey = !peerDraft.showKey; draw(); return; }
    if (d.action === 'new-event' && field(snapshot, 'EventsWritable', true)) { startEventEditor(null); return; }
    if (d.action === 'cancel-event') { eventDraft = null; pendingEventSave = null; draw(); return; }
    if (titles[state.mode][d.action]) navigate(d.action);
  }
  function handleInput(event) {
    const element = event.target;
    if (element.dataset.peerField) { peerDraft[element.dataset.peerField] = element.value; peerDraft.edited = true; }
    if (element.dataset.eventField && eventDraft) eventDraft[element.dataset.eventField] = element.type === 'checkbox' ? element.checked : element.value;
    if (element.id === ids() + '-search') { state.search = element.value.slice(0, 80); renderData(); }
    if (element.id === ids() + '-item-search') { state.itemSearch = element.value.slice(0, 80); renderItems(); clearTimeout(itemSearchTimer); itemSearchTimer = setTimeout(() => send('item-search', null, state.itemSearch), 250); }
  }
  function handleChange(event) {
    const element = event.target, d = element.dataset, id = ids();
    if (d.eventField && eventDraft) { eventDraft[d.eventField] = element.type === 'checkbox' ? element.checked : element.value; if (d.eventField === 'RecurrenceType') draw(); }
    else if (d.eventDay !== undefined && eventDraft) { const day = Number(d.eventDay); eventDraft.DaysOfWeek = eventDraft.DaysOfWeek.filter(value => value !== day); if (element.checked) eventDraft.DaysOfWeek.push(day); }
    else if (d.eventToggle) { if (field(snapshot, 'EventsWritable', true)) send('event-toggle', d.eventToggle, null, element.checked); }
    else if (d.alert) { const p = findPerson(d.character); if (!p || p.remote || !commands[d.alert]) return; send(commands[d.alert], p.id, null, element.checked); feedback(`${alertKinds.find(k => k[0] === d.alert)[1]} ${element.checked ? 'ativado' : 'desativado'} para ${p.name} · ${p.origin}.`); }
    else if (d.idle) {
      const p = findPerson(d.character), minutes = element.valueAsNumber; if (!p || p.remote || !['noItems', 'noXP'].includes(d.idle)) return;
      const error = root().querySelector('#' + CSS.escape(element.getAttribute('aria-describedby')));
      if (element.value.trim() === '' || !Number.isInteger(minutes) || minutes < 0 || minutes > 1440) { const message = 'Use 0 a 1440 min inteiros.'; errors.set(p.id + ':' + d.idle, message); element.setAttribute('aria-invalid', 'true'); element.setCustomValidity(message); if (error) error.textContent = message; return; }
      errors.delete(p.id + ':' + d.idle); element.removeAttribute('aria-invalid'); element.setCustomValidity(''); if (error) error.textContent = '';
      send(d.idle === 'noItems' ? 'drop-minutes' : 'xp-minutes', p.id, null, false, minutes);
      feedback(`${p.name} · ${p.origin}: ${minutes === 0 ? 'aviso desativado' : 'avisar após ' + minutes + ' min ' + (d.idle === 'noXP' ? 'sem XP' : 'sem drop')}.`);
    } else if (element.hasAttribute('data-monitor-all')) {
      const scope = (state.view === 'alerts' ? alertPeople() : selectedRows()).filter(p => !p.remote); for (const p of scope) send('monitor', p.id, null, element.checked);
      feedback(`Monitoramento ${element.checked ? 'ativado' : 'pausado'} para ${scope.length} personagens deste PC.`);
    } else if (element.id === id + '-sound') send('sound', null, null, element.checked);
    else if (element.id === id + '-pc') { state.pc = ['all', '1', '2'].includes(element.value) ? element.value : 'all'; renderData(); }
    else if (element.id === id + '-item-pc') { state.itemPc = ['all', '1', '2'].includes(element.value) ? element.value : 'all'; renderItems(); }
    else if (element.id === id + '-appearance') { state.appearance = element.value; draw(); send('appearance', null, state.appearance); }
    else if (element.id === id + '-density') { state.density = element.value; draw(); send('density', null, state.density); }
  }
  function handleSubmit(event) {
    const form = event.target;
    if (form.hasAttribute('data-peer-form')) {
      event.preventDefault();
      if (!field(field(snapshot, 'Peer', {}), 'IdentityAvailable', true)) return;
      const address = peerDraft.address.trim(), key = peerDraft.key.trim();
      if (!address || !key) { feedback('Informe o IP do outro computador e a mesma chave nos dois PCs.'); return; }
      send('peer-connect', null, JSON.stringify({ address, key })); feedback('Conectando os computadores…');
    } else if (form.hasAttribute('data-event-editor')) {
      event.preventDefault();
      if (!eventDraft || !field(snapshot, 'EventsWritable', true)) return;
      const times = eventDraft.Times.split(/[,;\s]+/).map(value => value.trim()).filter(Boolean);
      const offsets = eventDraft.ReminderOffsets.split(/[,;\s]+/).map(value => value.trim()).filter(Boolean);
      if (!eventDraft.Name.trim() || !times.length || times.some(time => !/^([01]\d|2[0-3]):[0-5]\d$/.test(time))) { feedback('Informe o nome e horários no formato HH:mm, por exemplo 11:00, 17:00.'); return; }
      if (offsets.some(value => !/^\d+$/.test(value) || Number(value) > 10080)) { feedback('Os avisos devem conter minutos inteiros entre 0 e 10080.'); return; }
      if (eventDraft.RecurrenceType === 'WEEKLY' && !eventDraft.DaysOfWeek.length) { feedback('Selecione pelo menos um dia da semana.'); return; }
      const payload = { Id: eventDraft.Id, Name: eventDraft.Name.trim(), Enabled: eventDraft.Enabled, TimeZone: eventDraft.TimeZone.trim(), RecurrenceType: eventDraft.RecurrenceType, Times: Array.from(new Set(times)).sort(), DaysOfWeek: eventDraft.RecurrenceType === 'WEEKLY' ? Array.from(new Set(eventDraft.DaysOfWeek)).sort() : [], DayOfMonth: eventDraft.RecurrenceType === 'MONTHLY' ? Number(eventDraft.DayOfMonth) : 0, SpecificDate: eventDraft.RecurrenceType === 'ONCE' ? eventDraft.SpecificDate : '', ReminderOffsets: Array.from(new Set(offsets.map(Number))).sort((a, b) => a - b), Notes: eventDraft.Notes.trim() };
      pendingEventSave = payload; send('event-save', null, JSON.stringify(payload)); feedback('Salvando evento…');
    }
  }
  function receive(message) {
    if (typeof message === 'string') { try { message = JSON.parse(message); } catch (_) { return; } }
    if (!message || typeof message !== 'object') return;
    if (message.kind === 'snapshot' && message.snapshot && typeof message.snapshot === 'object') {
      snapshot = message.snapshot; received = true; revision++;
      if (!peerDraft.edited) peerDraft.address = String(field(field(snapshot, 'Peer', {}), 'Address', ''));
      if (roots[message.mode]) state.mode = message.mode;
      if (['system', 'light', 'dark'].includes(message.appearance)) state.appearance = message.appearance;
      if (['normal', 'compact'].includes(message.density)) state.density = message.density;
      let saved = false;
      if (pendingEventSave) {
        saved = eventDefinitions().some(event => eventMatches(event, pendingEventSave));
        if (saved) { eventDraft = null; pendingEventSave = null; }
      }
      draw(); if (saved) feedback('Evento salvo.');
    } else if (message.kind === 'navigate' && titles[state.mode][message.page || message.view]) { state.view = message.page || message.view; state.selected = null; draw(); }
    else if (message.kind === 'peer-key' && typeof message.key === 'string' && message.key.length <= 512) { peerDraft.key = message.key; draw(); feedback('Chave gerada. Use a mesma chave nos dois computadores.'); }
    else if (message.kind === 'item-query' && typeof message.query === 'string') { state.itemSearch = message.query.slice(0, 80); state.itemPc = '1'; state.view = 'items'; draw(); send('item-search', null, state.itemSearch); }
    else if (message.kind === 'error') { pendingEventSave = null; feedback(String(message.message || 'Não foi possível concluir a ação.')); }
  }
  for (const element of Object.values(roots)) {
    element.addEventListener('click', handleClick); element.addEventListener('input', handleInput); element.addEventListener('change', handleChange); element.addEventListener('submit', handleSubmit);
    element.addEventListener('dblclick', event => { const row = event.target.closest('[data-inventory-key]'); if (row && row.dataset.inventoryKey) send('inventory', row.dataset.inventoryKey); });
  }
  if (window.chrome && window.chrome.webview) window.chrome.webview.addEventListener('message', event => receive(event.data));
  // A read-only diagnostic surface for the desktop fixture; it cannot mutate production data.
  Object.defineProperty(window, 'wydDesktop', { value: Object.freeze({ getState: () => Object.freeze(JSON.parse(JSON.stringify({ ...state, received, revision, characters: field(snapshot, 'Characters', []), items: field(snapshot, 'Items', []) }))) }), writable: false, configurable: false });
  draw(); send('ready');
})();
