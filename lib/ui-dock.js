/*!
 * ui-dock.js — パネルを浮かせる・つなげる・端にドックする（共通の部品）
 *
 * 次元おりがみ（hypercube.html）のメニューの「分離」パネル（Photoshop 風の連結・タブ・たたみ・端のドック・並びの保存）と、
 * 説明文の「📖 [説明]」たたみを、どのアプリでも使えるように取り出したもの。依存なし。使い方・仕様は同じフォルダの README.md を参照。
 *
 *   const dock = UIDock.create({ prefix: 'hypercube', onResize: () => onWindowResize(), onChange: () => requestRender(5) });
 *   document.querySelectorAll('.sb-panel > section.sb-sec').forEach(sec => dock.add(sec, { handle: sec.querySelector('.sb-h') }));
 *   dock.restore();                                       // 保存した並び（hypercubeFloats）に戻す
 *   UIDock.explToggles(['ui-overlay', ...dock.roots()]);  // 説明文をたたむ
 *
 * 保存の形：{ v:2, stacks:[{ x, y, ids:[…], collapsed?, tabs?, active? }], left:[…], right:[…] }（昔の { 名前:{x,y}|{dock} } も読める）
 */
(function (global) {
    'use strict';

    const VERSION = '1.0.0';
    const TEXT = {
        float: '⇱ 分離', home: '⇲ 戻す', homeAll: '⇲ 全部戻す', grip: 'まとめて移動',
        fold: '▾ たたむ', unfold: '▸ ひらく', tabs: '▤ タブ', rows: '☰ 縦並び', count: '（{n}枚）',
        floatTitle: 'この欄を切り離して浮かせる（見出しをドラッグしても分離できます。ほかのパネルに重ねると連結・間に差し込み。端に寄せるとドック。「戻す」で元の場所へ）',
        homeTitle: '元の場所へ戻す',
        gripTitle: 'つかんでグループごと移動（端に寄せるとドック、ほかのパネルに重ねると連結）',
        foldTitle: 'グループをまとめてたたむ／ひらく（つまみのダブルクリックでも）',
        tabsTitle: 'タブでまとめる（選んだ1枚だけ表示）／縦に並べる',
        homeAllTitle: 'このグループのパネルを全部元の場所へ',
        tabTitle: '：クリックで切り替え。ドラッグで取り出す・ほかのグループや端へ移す',
        tabHomeTitle: '表示中のパネルを元の場所へ',
    };

    // ---------------------------------------------------------------- 既定の CSS（色は変数。アプリの CSS が後から上書きできるよう head の先頭に入れる）
    const CSS = `
:root { --uid-rail-w: min(340px, 32vw); --uid-accent: #a5b4fc; --uid-border: rgba(129, 140, 248, 0.55); --uid-panel-bg: rgba(4, 8, 22, 0.96); --uid-head-bg: rgba(7, 11, 26, 0.98);
    --uid-grip-bg: rgba(30, 27, 75, 0.96); --uid-rail-bg: rgba(2, 5, 16, 0.95); --uid-muted: #8aa0c6; --uid-text: #e2e8f0; --uid-tab-bg: rgba(30, 41, 59, 0.7); --uid-tab-on: rgba(76, 29, 149, 0.6); }
body { --dock-l: 0px; --dock-r: 0px; }
body.dock-left-on { --dock-l: var(--uid-rail-w); }
body.dock-right-on { --dock-r: var(--uid-rail-w); }
.uid-layer { position: fixed; inset: 0; z-index: 45; pointer-events: none; }
.float-panel { position: absolute; width: min(330px, 92vw); max-height: 82vh; overflow-y: auto; overflow-x: hidden; pointer-events: auto; border-radius: 12px; box-shadow: 0 12px 44px rgba(0, 0, 0, 0.6); }
.float-panel.docked { position: static !important; width: 100% !important; max-height: none !important; left: auto !important; top: auto !important; box-shadow: none; flex: 0 0 auto; overflow: visible; }
.float-panel > .uid-panel { margin: 0; background: var(--uid-panel-bg); border-color: var(--uid-border); }
.float-panel .uid-handle { cursor: move; position: sticky; top: 0; z-index: 5; background: var(--uid-head-bg); box-shadow: 0 1px 0 rgba(129, 140, 248, 0.3); }
.uid-panel:not(.floating) .uid-handle, .uid-trigger { cursor: grab; user-select: none; -webkit-user-select: none; }
.uid-handle button, .uid-trigger button { cursor: pointer; }
.sb-floatbtn { margin-left: 6px; flex-shrink: 0; font-size: 10px; font-weight: 400; color: var(--uid-muted); cursor: pointer; white-space: nowrap; background: none; border: 0; padding: 0 2px; font-family: inherit; }
.sb-floatbtn:hover { color: var(--uid-text); }
.uid-panel.floating .uid-handle .sb-floatbtn { color: var(--uid-accent); }
.dock-rail { position: fixed; top: 0; bottom: 0; z-index: 44; width: 0; overflow: hidden; pointer-events: none; display: flex; flex-direction: column; gap: 8px; padding: 0; box-sizing: border-box; background: var(--uid-rail-bg); }
.dock-rail.active { pointer-events: auto; overflow-y: auto; overflow-x: hidden; padding: 8px; }
.dock-rail.uid-left { left: 0; width: var(--dock-l); border-right: 1px solid rgba(129, 140, 248, 0.4); }
.dock-rail.uid-right { right: 0; width: var(--dock-r); border-left: 1px solid rgba(129, 140, 248, 0.4); }
.float-stack { position: absolute; width: min(330px, 92vw); max-height: 82vh; overflow-y: auto; overflow-x: hidden; pointer-events: auto; border-radius: 12px; box-shadow: 0 12px 44px rgba(0, 0, 0, 0.6); display: flex; flex-direction: column; gap: 6px; }
.float-stack > .fs-grip { display: none; }
.float-stack.multi { background: rgba(4, 8, 22, 0.55); border: 1px solid rgba(129, 140, 248, 0.35); padding: 0 4px 4px; }
.float-stack.multi > .fs-grip { display: flex; align-items: center; gap: 6px; position: sticky; top: 0; z-index: 6; height: 24px; flex: 0 0 auto; box-sizing: border-box; cursor: move; user-select: none; -webkit-user-select: none; touch-action: none; font-size: 10px; color: var(--uid-accent); padding: 0 8px; margin: 0 -4px; background: var(--uid-grip-bg); border-bottom: 1px solid rgba(129, 140, 248, 0.35); }
.float-stack.multi .float-panel .uid-handle { top: 24px; }
.fs-grip .fs-dots { font-size: 13px; letter-spacing: -1px; }
.fs-grip .fs-fold { margin-left: auto; }
.fs-grip .fs-count { color: var(--uid-muted); }
.float-stack.joining { opacity: 0.55; }
.float-stack.collapsed > .float-panel { display: none; }
.float-stack.collapsed { padding-bottom: 0; }
.float-stack.collapsed > .fs-grip { margin-bottom: 0; border-bottom: 0; border-radius: 11px; }
.float-stack.tabbed > .float-panel:not(.tab-on) { display: none; }
.float-stack.tabbed > .float-panel .uid-handle { display: none; }
.float-stack.tabbed > .float-panel > .uid-panel { padding-top: 10px; border-top-left-radius: 0; border-top-right-radius: 0; }
.float-stack.tabbed { gap: 0; }
.float-stack > .fs-tabs { display: flex; flex-wrap: wrap; align-items: flex-end; gap: 3px; position: sticky; top: 24px; z-index: 6; margin: 4px -4px 0; padding: 4px 6px 0; background: var(--uid-head-bg); border-bottom: 1px solid rgba(167, 139, 250, 0.55); }
.float-stack.collapsed > .fs-tabs { display: none; }
.fs-tab { font-size: 11px; line-height: 1.2; padding: 5px 10px; border-radius: 7px 7px 0 0; color: #94a3b8; background: var(--uid-tab-bg); border: 1px solid rgba(71, 85, 105, 0.7); border-bottom: 0; cursor: pointer; user-select: none; touch-action: none; font-family: inherit; }
.fs-tab:hover { color: var(--uid-text); }
.fs-tab.on { color: #ede9fe; background: var(--uid-tab-on); border-color: rgba(167, 139, 250, 0.75); }
.fs-tabs .fs-tab-back { margin-left: auto; align-self: center; }
.uid-ins { position: fixed; z-index: 47; height: 4px; border-radius: 2px; background: var(--uid-accent); box-shadow: 0 0 10px rgba(165, 180, 252, 0.9); pointer-events: none; display: none; }
.uid-hint { position: fixed; top: 0; bottom: 0; z-index: 46; pointer-events: none; display: none; background: rgba(129, 140, 248, 0.16); border: 2px dashed rgba(129, 140, 248, 0.75); border-radius: 10px; box-sizing: border-box; }
.expl-tg { display: inline-flex; align-items: center; gap: 3px; align-self: flex-start; font-size: 10px; line-height: 1.4; color: var(--uid-muted); background: none; border: 0; padding: 0; cursor: pointer; white-space: nowrap; font-family: inherit; }
.expl-tg:hover { color: var(--uid-text); }
.expl-tg .expl-ic { flex-shrink: 0; transition: transform .15s; }
.expl-tg:hover .expl-ic { transform: translateY(-1px); }
.expl-closed { display: none !important; }
`;
    function injectCss() {
        if (typeof document === 'undefined' || document.getElementById('ui-dock-css')) return;
        const st = document.createElement('style'); st.id = 'ui-dock-css'; st.textContent = CSS;
        document.head.insertBefore(st, document.head.firstChild);
    }

    // ---------------------------------------------------------------- 保存の形をそろえる（v2。昔の { 名前:{x,y}|{dock} } も読みかえる）
    function readLayout(o) {
        if (typeof o === 'string') { try { o = JSON.parse(o); } catch (_) { o = null; } }
        const out = { v: 2, stacks: [], left: [], right: [] };
        if (!o || typeof o !== 'object' || Array.isArray(o)) return out;
        const names = a => Array.isArray(a) ? a.filter(s => typeof s === 'string' && s) : [];
        if (o.v === 2) {
            out.left = names(o.left); out.right = names(o.right);
            (Array.isArray(o.stacks) ? o.stacks : []).forEach(s => {
                if (!s || typeof s !== 'object') return;
                const ids = names(s.ids); if (!ids.length) return;
                const t = { x: Number.isFinite(s.x) ? s.x : null, y: Number.isFinite(s.y) ? s.y : null, ids };
                if (s.collapsed) t.collapsed = true;
                if (s.tabs) { t.tabs = true; if (typeof s.active === 'string') t.active = s.active; }
                out.stacks.push(t);
            });
            return out;
        }
        Object.keys(o).forEach(fid => {   // 昔の形：欄ごとに位置かドック
            const s = o[fid]; if (!s || typeof s !== 'object') return;
            if (s.dock === 'left' || s.dock === 'right') out[s.dock].push(fid);
            else out.stacks.push({ x: Number.isFinite(s.x) ? s.x : null, y: Number.isFinite(s.y) ? s.y : null, ids: [fid] });
        });
        return out;
    }

    const lsSafe = {
        getItem(k) { try { return localStorage.getItem(k); } catch (_) { return null; } },
        setItem(k, v) { try { localStorage.setItem(k, v); } catch (_) {} },
    };
    const call = (f, ...a) => { if (typeof f === 'function') { try { f(...a); } catch (e) { console.error('[ui-dock]', e); } } };
    const titleOfDefault = h => h ? [...h.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('').replace(/\s+/g, ' ').trim()
        || h.textContent.replace(/\s+/g, ' ').trim() : '';
    const tabLabelDefault = id => id.replace(/（[^）]*）/g, '').trim() || id;   // タブ名はかっこ書きを省いて短く
    const NODRAG = 'button, input, select, textarea, label, a';

    // ======================================================================
    // create：1 つのページに 1 つ
    // ======================================================================
    function create(opts) {
        opts = opts || {};
        const T = Object.assign({}, TEXT, opts.text);
        const store = opts.storage || lsSafe;
        const KEY = opts.key || (opts.prefix || 'app') + 'Floats';
        const SNAP = Number.isFinite(opts.snap) ? opts.snap : 52;
        const DOCK_MINW = Number.isFinite(opts.dockMinWidth) ? opts.dockMinWidth : 820;
        const ID = Object.assign({ layer: 'float-layer', left: 'dock-left', right: 'dock-right', hint: 'dock-hint', ins: 'dock-ins' }, opts.ids);
        const titleOf = opts.titleOf || titleOfDefault, tabLabel = opts.tabLabel || tabLabelDefault;
        const onResize = () => call(opts.onResize), onChange = () => call(opts.onChange);
        if (opts.css !== false) injectCss();
        if (opts.railWidth) document.documentElement.style.setProperty('--uid-rail-w', opts.railWidth);

        const mk = (id, cls) => { const e = document.createElement('div'); e.id = id; e.className = cls; document.body.appendChild(e); return e; };
        const layer = mk(ID.layer, 'uid-layer');
        const railL = mk(ID.left, 'dock-rail uid-left'); railL._side = 'left';
        const railR = mk(ID.right, 'dock-rail uid-right'); railR._side = 'right';
        const hint = mk(ID.hint, 'uid-hint');
        const insLine = mk(ID.ins, 'uid-ins');

        const panels = new Map();   // id → { id, el, handle, btn, wrap, mark, portable, tbtns }
        let cascade = 0, restoring = false;
        const clampX = (x, el) => { const ww = el.offsetWidth || 330; return Math.max(4, Math.min(window.innerWidth - ww - 4, x)); };
        const clampY = y => Math.max(4, Math.min(window.innerHeight - 42, y));
        const wrapsIn = c => [...c.querySelectorAll(':scope > .float-panel')];
        const isRail = c => c === railL || c === railR;
        const stackEls = () => [...layer.querySelectorAll(':scope > .float-stack')];

        function layout() {   // 今の並び（DOM）をそのまま
            const ids = c => wrapsIn(c).map(w => w._p.id);
            return {
                v: 2,
                stacks: stackEls().map(st => ({ x: parseInt(st.style.left) || 0, y: parseInt(st.style.top) || 0, ids: ids(st),
                    ...(st.classList.contains('collapsed') ? { collapsed: true } : {}),
                    ...(st.classList.contains('tabbed') ? { tabs: true, active: st._active } : {}) })).filter(s => s.ids.length),
                left: ids(railL), right: ids(railR),
            };
        }
        function save() { if (!restoring) store.setItem(KEY, JSON.stringify(layout())); }

        // レールの中身の有無で、描画の場所を広げ／狭める（--dock-l/r）
        function refreshDock(side) {
            const rail = side === 'left' ? railL : railR, has = wrapsIn(rail).length > 0;
            const was = rail.classList.contains('active');
            rail.classList.toggle('active', has);
            document.body.classList.toggle('dock-' + side + '-on', has);
            if (was !== has) onResize();
            onChange();
        }
        // 入れ物（浮いているグループ or 端のレール）の後始末：空のグループは消す、2枚以上なら「まとめて移動」のつまみを出す
        function tidy(c) {
            if (!c) return;
            if (isRail(c)) { refreshDock(c._side); return; }
            const n = wrapsIn(c).length;
            onChange();
            if (!n) { c.remove(); return; }
            c.classList.toggle('multi', n > 1);
            if (n < 2) c.classList.remove('collapsed');   // つまみが無いとひらけないので、1枚ならたたまない
            syncFold(c); syncTabs(c);
            c.style.left = clampX(parseInt(c.style.left) || 0, c) + 'px';
        }
        const sbtn = (text, title, cls) => { const b = document.createElement('button'); b.type = 'button'; b.className = 'sb-floatbtn' + (cls ? ' ' + cls : ''); if (text) b.textContent = text; if (title) b.title = title; return b; };
        function newStack(x, y) {   // 浮いているグループ（縦に連結したパネルの入れ物）
            const st = document.createElement('div'); st.className = 'float-stack';
            const grip = document.createElement('div'); grip.className = 'fs-grip'; grip.title = T.gripTitle;
            grip.innerHTML = '<span class="fs-dots">⠿</span><span class="fs-label"></span><span class="fs-count"></span>';
            grip.querySelector('.fs-label').textContent = T.grip;
            const fold = sbtn('', T.foldTitle, 'fs-fold');
            fold.addEventListener('click', e => { e.stopPropagation(); toggleFold(st); });
            grip.addEventListener('dblclick', e => { if (e.target.closest('button')) return; toggleFold(st); });
            const tabb = sbtn('', T.tabsTitle, 'fs-tabbtn');
            tabb.addEventListener('click', e => { e.stopPropagation(); st.classList.toggle('tabbed'); syncTabs(st); save(); onChange(); });
            const all = sbtn(T.homeAll, T.homeAllTitle);
            all.addEventListener('click', e => { e.stopPropagation(); wrapsIn(st).forEach(w => goHome(w._p)); });
            grip.append(tabb, fold, all); st.appendChild(grip);
            layer.appendChild(st);
            st.style.left = clampX(x, st) + 'px'; st.style.top = clampY(y) + 'px';
            grip.addEventListener('pointerdown', e => { if (e.button !== 0 || e.target.closest('button')) return; dragStack(st, e); });
            return st;
        }
        function syncFold(st) {   // たたみボタンの文字と、たたんでいるときの枚数
            const b = st.querySelector(':scope > .fs-grip .fs-fold'), cnt = st.querySelector(':scope > .fs-grip .fs-count'); if (!b) return;
            const col = st.classList.contains('collapsed');
            b.textContent = col ? T.unfold : T.fold;
            if (cnt) cnt.textContent = col ? T.count.replace('{n}', wrapsIn(st).length) : '';
        }
        // タブでまとめる：見出しの代わりに上にタブを並べ、選んだ1枚だけ表示。タブはクリックで切替、ドラッグで取り出し・ほかへ移動
        function syncTabs(st) {
            const tb = st.querySelector(':scope > .fs-grip .fs-tabbtn');
            const items = wrapsIn(st); let bar = st.querySelector(':scope > .fs-tabs');
            if (!st.classList.contains('tabbed') || items.length < 2) {
                if (items.length < 2) st.classList.remove('tabbed');
                if (bar) bar.remove(); items.forEach(w => w.classList.remove('tab-on'));
                if (tb) tb.textContent = st.classList.contains('tabbed') ? T.rows : T.tabs;
                return;
            }
            if (tb) tb.textContent = T.rows;
            const act = items.find(w => w._p.id === st._active) || items[0]; st._active = act._p.id;
            if (!bar) { bar = document.createElement('div'); bar.className = 'fs-tabs'; st.querySelector(':scope > .fs-grip').after(bar); }
            bar.innerHTML = '';
            items.forEach(w => {
                const fid = w._p.id, t = document.createElement('button'); t.type = 'button';
                t.className = 'fs-tab' + (w === act ? ' on' : ''); t.textContent = tabLabel(fid); t.title = fid + T.tabTitle;
                t.addEventListener('pointerdown', e => { if (e.button !== 0) return; if (e.pointerType !== 'touch') e.preventDefault(); armDrag(e, ev => { t._dragged = true; beginDrag(w._p, ev); }); });
                t.addEventListener('click', e => { e.stopPropagation(); if (t._dragged) { t._dragged = false; return; } st._active = fid; syncTabs(st); save(); onChange(); });
                bar.appendChild(t); w.classList.toggle('tab-on', w === act);
            });
            const back = sbtn(T.home, T.tabHomeTitle, 'fs-tab-back');
            back.addEventListener('click', e => { e.stopPropagation(); goHome(act._p); });
            bar.appendChild(back);
        }
        function toggleFold(st, on) {   // グループをまとめてたたむ（つまみだけ残す）／ひらく
            st.classList.toggle('collapsed', on === undefined ? !st.classList.contains('collapsed') : on);
            syncFold(st); st.style.top = clampY(parseInt(st.style.top) || 0) + 'px'; save(); onChange();
        }
        function insertWrap(wrap, c, index) {   // 入れ物 c の index 番目（上から）に差し込む
            const items = wrapsIn(c).filter(w => w !== wrap);
            const ref = items[index] || null;
            if (ref) c.insertBefore(wrap, ref); else c.appendChild(wrap);
        }
        function indexByY(c, y) {   // ポインタの高さから、何番目に差し込むか（各パネルの上下の真ん中で判定）
            const items = wrapsIn(c);
            for (let i = 0; i < items.length; i++) { const r = items[i].getBoundingClientRect(); if (y < r.top + r.height / 2) return i; }
            return items.length;
        }
        const wide = () => window.innerWidth >= DOCK_MINW;
        function edgeSide(x) { if (!wide()) return null; if (x <= SNAP) return 'left'; if (x >= window.innerWidth - SNAP) return 'right'; return null; }
        function showHint(side) {   // ドロップ先の帯：レールの今の位置（アプリの CSS でずらしていてもそれに合わせる）に、レールの幅で
            if (!side) { hint.style.display = 'none'; return; }
            const rail = side === 'left' ? railL : railR, shown = getComputedStyle(rail).display !== 'none', r = rail.getBoundingClientRect();
            hint.style.width = 'var(--uid-rail-w)'; hint.style.display = 'block';
            if (side === 'left') { hint.style.right = ''; hint.style.left = (shown ? r.left : 0) + 'px'; }
            else { hint.style.left = ''; hint.style.right = (shown ? window.innerWidth - r.right : 0) + 'px'; }
        }
        function showIns(t) {   // 差し込み位置の線（グループやレールの、パネルとパネルの間）
            if (!t || !t.c || !wrapsIn(t.c).length) { insLine.style.display = 'none'; return; }
            const items = wrapsIn(t.c), cr = t.c.getBoundingClientRect();
            const line = (left, width, top) => { insLine.style.left = left + 'px'; insLine.style.width = Math.max(40, width) + 'px'; insLine.style.top = top + 'px'; insLine.style.display = 'block'; };
            const tbar = t.c.querySelector(':scope > .fs-tabs');
            if (t.c.classList.contains('tabbed') && tbar && !t.c.classList.contains('collapsed')) { const br = tbar.getBoundingClientRect(); line(br.left + 6, br.width - 12, br.bottom - 2); return; }
            if (t.c.classList.contains('collapsed')) { line(cr.left + 6, cr.width - 12, cr.bottom - 2); return; }
            const y = t.index < items.length ? items[t.index].getBoundingClientRect().top - 4 : items[items.length - 1].getBoundingClientRect().bottom + 4;
            line(cr.left + 6, cr.width - 12, Math.max(cr.top, Math.min(cr.bottom, y)) - 2);
        }
        function findTarget(cx, cy, self) {   // ドロップ先：端（レール）／ほかのグループの上／ドック中のレールの上
            const side = edgeSide(cx);
            if (side) { const rail = side === 'left' ? railL : railR; return { c: rail, index: indexByY(rail, cy), side }; }
            const inside = el => { const r = el.getBoundingClientRect(); return r.width > 0 && cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom; };
            const stacks = stackEls().filter(st => st !== self).reverse();   // 上に重なっているものから
            for (const st of stacks) if (inside(st)) return { c: st, index: (st.classList.contains('tabbed') || st.classList.contains('collapsed')) ? wrapsIn(st).length : indexByY(st, cy) };   // タブ・たたみ中は末尾へ
            for (const rail of [railL, railR]) if (rail.classList.contains('active') && inside(rail)) return { c: rail, index: indexByY(rail, cy), side: rail._side };
            return null;
        }
        // グループをつかんで動かす。離した場所が端ならドック、ほかのグループやレールの上なら、その位置に連結（間に差し込み）
        function dragStack(st, e, started) {   // started：すでに少し動かしてから始めた（見出し・タブのドラッグ）
            const sx = e.clientX, sy = e.clientY, ox = parseInt(st.style.left) || 0, oy = parseInt(st.style.top) || 0;
            let moved = !!started, tgt = null;
            layer.appendChild(st);   // 一番手前へ
            const mv = ev => {
                const cx = ev.clientX, cy = ev.clientY, dx = cx - sx, dy = cy - sy;
                if (Math.abs(dx) + Math.abs(dy) > 3) moved = true;
                st.style.left = clampX(ox + dx, st) + 'px'; st.style.top = clampY(oy + dy) + 'px';
                tgt = moved ? findTarget(cx, cy, st) : null;
                showHint(tgt && tgt.side && edgeSide(cx) ? tgt.side : null); showIns(tgt);
                st.classList.toggle('joining', !!tgt);
            };
            const end = () => {
                window.removeEventListener('pointermove', mv); window.removeEventListener('pointerup', end); window.removeEventListener('pointercancel', end);
                showHint(null); showIns(null); st.classList.remove('joining');
                if (moved && tgt) {   // 連結：グループのパネルを順番そのままで差し込む
                    const ws = wrapsIn(st); if (ws.length && tgt.c.classList.contains('tabbed')) tgt.c._active = ws[0]._p.id;   // タブのグループへ入れたら、入れた1枚を表示
                    ws.forEach((w, i) => insertWrap(w, tgt.c, tgt.index + i));
                    st.remove(); tidy(tgt.c);
                } else onChange();
                save();
            };
            window.addEventListener('pointermove', mv); window.addEventListener('pointerup', end); window.addEventListener('pointercancel', end);
            e.preventDefault();
        }
        function armDrag(e, onStart) {   // 少し（4px）動かしたらドラッグ開始。動かさなければふつうのクリック
            const sx = e.clientX, sy = e.clientY;
            const off = () => { window.removeEventListener('pointermove', mv); window.removeEventListener('pointerup', off); window.removeEventListener('pointercancel', off); };
            const mv = ev => { if (Math.abs(ev.clientX - sx) + Math.abs(ev.clientY - sy) > 4) { off(); onStart(ev); } };
            window.addEventListener('pointermove', mv); window.addEventListener('pointerup', off); window.addEventListener('pointercancel', off);
        }
        function beginDrag(P, ev) {   // 浮いている欄を動かす。1枚だけのグループならグループごと、連結中・タブ中・ドック中なら1枚だけ抜き出す
            const wrap = P.wrap; if (!wrap) return;
            let st = wrap.parentNode;
            if (isRail(st) || wrapsIn(st).length > 1) {
                const from = st, wasTab = from.classList.contains('tabbed');
                const r = (wasTab ? from : wrap).getBoundingClientRect();   // タブから抜くときは、グループの位置から
                st = newStack(r.left, r.top); insertWrap(wrap, st, 0); wrap.classList.remove('tab-on'); tidy(from); tidy(st);
                st.style.left = clampX(ev.clientX - 60, st) + 'px'; st.style.top = clampY(ev.clientY - 14) + 'px';   // つかんだ所の近くに見出しが来るように
            }
            dragStack(st, ev, true);
        }
        function detachAt(wrap, ev) {   // 元の場所から直接ドラッグ：切り離して、つかんだ位置のまま浮かせて動かし始める
            const st = newStack(ev.clientX - 60, ev.clientY - 14); insertWrap(wrap, st, 0); tidy(st);
            st.style.left = clampX(ev.clientX - 60, st) + 'px'; st.style.top = clampY(ev.clientY - 14) + 'px';
            dragStack(st, ev, true);
        }
        // 見出しのドラッグ（元の場所の見出しも、浮いた欄の見出しも）。ドラッグの直後のクリックは止める（ボタンは通す）
        function dragHandle(handle, onArm, canStart) {
            let moved = false;
            handle.addEventListener('pointerdown', e => {
                moved = false;
                if (e.button !== 0 || e.target.closest(NODRAG) || !canStart(e)) return;
                if (e.pointerType !== 'touch') e.preventDefault();   // 文字の選択を始めない
                armDrag(e, ev => { moved = true; onArm(ev); });
            });
            handle.addEventListener('click', e => { if (moved && !e.target.closest(NODRAG)) { e.stopPropagation(); e.preventDefault(); } moved = false; }, true);
        }
        function syncBtns(P) {
            const t = P.wrap ? T.home : T.float;
            if (P.btn) { P.btn.textContent = t; P.btn.title = P.wrap ? T.homeTitle : T.floatTitle; }
            P.tbtns.forEach(b => { b.textContent = t; b.title = P.wrap ? T.homeTitle : T.floatTitle; });
        }
        function setupEl(P) {   // パネルの要素に印・ボタン・ドラッグを付ける
            P.el.classList.add('uid-panel'); P.el.dataset.fid = P.id;
            if (!P.handle) return;
            P.handle.classList.add('uid-handle');
            if (P.button) {
                P.btn = sbtn(T.float, T.floatTitle);
                P.btn.addEventListener('click', e => { e.stopPropagation(); if (P.wrap) goHome(P); else floatP(P); });
                P.handle.appendChild(P.btn);
            }
            // 浮いている欄はタッチでもドラッグ。元の場所の欄はマウス・ペンだけ（タッチはスクロールと区別できないので「分離」ボタンで）
            dragHandle(P.handle, ev => { if (P.wrap) beginDrag(P, ev); else detachAt(prep(P), ev); }, e => !!P.wrap || e.pointerType !== 'touch');
            syncBtns(P);
        }
        function defaultPos() { const p = { x: Math.round(window.innerWidth * 0.42) + (cascade % 3) * 22, y: 70 + (cascade % 6) * 28 }; cascade++; return p; }
        function prep(P) {   // 欄を切り離して枠に入れる（置き場所はまだ）
            if (P.wrap) return P.wrap;
            if (P.portable) {
                if (!P.el) {
                    P.el = P.portable.build();
                    P.handle = typeof P.portable.handle === 'function' ? P.portable.handle(P.el) : (P.portable.handle || P.el.firstElementChild);
                    setupEl(P);
                }
                call(P.portable.onFloat, P.el);
            } else {   // 元の場所に目印（コメント）を置く。前後の欄も浮いていても、戻す時に元の順に戻る
                P.mark = document.createComment('ui-dock:' + P.id);
                P.el.parentNode.insertBefore(P.mark, P.el);
            }
            const wrap = document.createElement('div'); wrap.className = 'float-panel docked';
            wrap.appendChild(P.el); wrap._p = P; P.wrap = wrap;
            P.el.classList.add('floating'); syncBtns(P);
            return wrap;
        }
        function goHome(P) {   // 元の場所へ（浮き・連結・ドックどこからでも）
            if (!P || !P.wrap) return;
            const wrap = P.wrap, c = wrap.parentNode;
            P.el.classList.remove('floating');
            if (P.portable) call(P.portable.onHome, P.el);   // 中身はアプリが今の場所へ戻す
            else if (P.mark && P.mark.parentNode) { P.mark.parentNode.insertBefore(P.el, P.mark); P.mark.remove(); }
            P.mark = null; wrap.remove(); P.wrap = null; syncBtns(P);
            tidy(c); save();
        }
        function floatP(P, pos) {   // 新しい1枚グループとして浮かせる
            if (P.wrap) return;
            const w = prep(P), p = pos && Number.isFinite(pos.x) && Number.isFinite(pos.y) ? pos : defaultPos(), st = newStack(p.x, p.y);
            insertWrap(w, st, 0); tidy(st); save();
        }
        function dockP(P, side) {
            if (!wide()) { if (!P.wrap) floatP(P); return; }   // 狭い画面ではドックしない
            const rail = side === 'left' ? railL : railR;
            const from = P.wrap ? P.wrap.parentNode : null, w = prep(P);
            if (from === rail) return;
            insertWrap(w, rail, wrapsIn(rail).length); if (from) tidy(from); tidy(rail); save();
        }
        const get = id => panels.get(id) || null;

        // ---------------------------------------------------------------- 登録
        function add(el, o) {
            o = o || {};
            if (!el) return null;
            const handle = o.handle || el.firstElementChild;
            const id = o.id || titleOf(handle);
            if (!id || panels.has(id)) return null;
            const P = { id, el, handle, button: o.button !== false, btn: null, wrap: null, mark: null, portable: null, tbtns: [] };
            panels.set(id, P); setupEl(P);
            return id;
        }
        function addPortable(id, o) {
            o = o || {};
            if (!id || panels.has(id) || typeof o.build !== 'function') return null;
            const P = { id, el: null, handle: null, button: o.button !== false, btn: null, wrap: null, mark: null, portable: o, tbtns: [] };
            panels.set(id, P);
            (o.triggers || []).filter(Boolean).forEach(h => {   // 元の場所の見出し：「分離」ボタンとドラッグ
                const b = sbtn(T.float, T.floatTitle);
                b.addEventListener('click', e => { e.stopPropagation(); if (P.wrap) goHome(P); else floatP(P); });
                h.appendChild(b); P.tbtns.push(b); h.classList.add('uid-trigger');
                dragHandle(h, ev => detachAt(prep(P), ev), e => !P.wrap && e.pointerType !== 'touch');
            });
            return id;
        }

        // ---------------------------------------------------------------- 保存した並びに戻す（昔の形は、1枚ずつのグループ／レールへ読みかえ）
        function restore(L) {
            if (L === undefined) L = store.getItem(KEY);
            L = readLayout(L);
            const used = new Set();
            const fill = (c, ids) => ids.forEach(fid => { const P = get(fid); if (!P || used.has(fid) || P.wrap) return; used.add(fid); insertWrap(prep(P), c, wrapsIn(c).length); });
            restoring = true;
            try {
                ['left', 'right'].forEach(side => {
                    const ids = L[side]; if (!ids.length) return;
                    if (wide()) { const rail = side === 'left' ? railL : railR; fill(rail, ids); tidy(rail); }
                    else { const p = defaultPos(), st = newStack(p.x, p.y); fill(st, ids); tidy(st); }   // 狭い画面ではドックせず、浮かせて出す
                });
                L.stacks.forEach(s => {
                    const p = (s.x !== null && s.y !== null) ? s : defaultPos(), st = newStack(p.x, p.y);
                    fill(st, s.ids); if (s.collapsed) st.classList.add('collapsed'); if (s.tabs) { st.classList.add('tabbed'); st._active = s.active; }
                    tidy(st);
                });
            } finally { restoring = false; }
        }
        function homeAll() {
            restoring = true;
            try { panels.forEach(P => goHome(P)); } finally { restoring = false; }
            save();
        }
        function apply(L) { restoring = true; try { panels.forEach(P => goHome(P)); } finally { restoring = false; } restore(L); save(); }

        // 窓の大きさが変わったら、浮いているグループを画面の中へ
        window.addEventListener('resize', () => stackEls().forEach(st => { st.style.left = clampX(parseInt(st.style.left) || 0, st) + 'px'; st.style.top = clampY(parseInt(st.style.top) || 0) + 'px'; }));

        return {
            add, addPortable, restore, save, layout, apply, homeAll,
            float: (id, pos) => { const P = get(id); if (P) floatP(P, pos); },
            dock: (id, side) => { const P = get(id); if (P && (side === 'left' || side === 'right')) dockP(P, side); },
            home: id => goHome(get(id)),
            isFloating: id => { const P = get(id); return !!(P && P.wrap); },
            where: id => { const P = get(id); if (!P || !P.wrap) return null; const c = P.wrap.parentNode; return c === railL ? 'left' : c === railR ? 'right' : 'float'; },
            ids: () => [...panels.keys()],
            roots: () => [layer, railL, railR],
            stacks: stackEls,
            key: KEY,
            els: { layer, left: railL, right: railR, hint, ins: insLine },
        };
    }

    // ======================================================================
    // 説明文を「📖 [説明]」で開閉
    // ======================================================================
    // 本のアイコン（フラットデザイン）：開いた本。左右のページを2色、まん中に綴じ目、ページに行
    const BOOK_ICON = '<svg class="expl-ic" width="15" height="11" viewBox="0 0 16 12" aria-hidden="true">'
        + '<path d="M8 2.2C6.2 1 3.8 .6 1 .9v9.4c2.8-.3 5.2.1 7 1.3z" fill="#a5b4fc"/>'
        + '<path d="M8 2.2C9.8 1 12.2 .6 15 .9v9.4c-2.8-.3-5.2.1-7 1.3z" fill="#818cf8"/>'
        + '<path d="M8 2.2v9.4" stroke="#312e81" stroke-width=".9"/>'
        + '<path d="M3 3.6h3.2M3 5.4h3.2M3 7.2h3.2M9.8 3.6h3.2M9.8 5.4h3.2M9.8 7.2h3.2" stroke="#eef2ff" stroke-width=".75" stroke-linecap="round"/>'
        + '</svg>';
    function explToggles(roots, o) {
        o = o || {};
        if (o.css !== false) injectCss();
        roots = (roots || []).map(r => typeof r === 'string' ? document.getElementById(r) : r).filter(Boolean);
        if (!roots.length) return [];
        const INTER = 'button, input, select, textarea, label, a, canvas, svg, img, kbd';
        const minLen = Number.isFinite(o.minLength) ? o.minLength : 25;
        const classRe = o.classRe || /text-\[(10|11)px\]|text-xs|text-slate-(300|400|500)/;
        const ids = o.ids || [];
        const label = o.label || '[説明]';
        const txtOf = el => el.textContent.replace(/\s+/g, ' ').trim();
        const isExpl = o.isExpl || (el => {
            if (el.classList.contains('expl-tg')) return false;
            if (el.matches('.expl, [data-expl]')) return true;                                     // 印の付いた説明は必ず
            if (el.id && !ids.includes(el.id)) return false;                                       // 状態表示（中身がプログラムで変わる）
            if (ids.includes(el.id)) return true;
            if (el.closest('[id$="-list"], [id$="-slots"], button, label, a, kbd')) return false;   // 一覧の中身（作り直される）・ボタンの中
            if (el.querySelector(INTER)) return false;                                             // 操作部品を含む＝説明だけの文ではない
            if (txtOf(el).length < minLen) return false;
            if (!classRe.test(String(el.className))) return false;
            if (el.tagName === 'SPAN' && !el.parentElement.querySelector(INTER)) return false;     // 文の中の span は親の文ごとたたむ
            return true;
        });
        const found = [];
        roots.forEach(r => r.querySelectorAll(o.selector || 'p, div, span').forEach(el => { if (!el.dataset.explDone && isExpl(el)) found.push(el); }));
        const made = [];
        found.filter(el => !found.some(x => x !== el && x.contains(el))).forEach(el => {   // いちばん外側のまとまりだけ
            el.dataset.explDone = '1';
            const b = document.createElement('button'); b.type = 'button'; b.className = 'expl-tg'; b.title = 'クリックで説明を開く／閉じる';
            ['d5-only', 'd4-only'].concat(o.copyClasses || []).forEach(c => { if (el.classList.contains(c)) { b.classList.add(c); if (el.classList.contains('hidden')) b.classList.add('hidden'); } });
            b.innerHTML = (o.icon === undefined ? BOOK_ICON : o.icon) + '<span class="expl-lb"></span>';
            const lb = b.querySelector('.expl-lb');
            const set = open => { el.classList.toggle('expl-closed', !open); lb.textContent = label + ' ' + (open ? '▴' : '▾'); };
            b.addEventListener('click', e => { e.stopPropagation(); set(el.classList.contains('expl-closed')); });
            el.parentNode.insertBefore(b, el); set(!!o.open);
            made.push(b);
        });
        return made;
    }

    global.UIDock = { VERSION, create, readLayout, explToggles, css: CSS, text: TEXT };
})(typeof window !== 'undefined' ? window : globalThis);
