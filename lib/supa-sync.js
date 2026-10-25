/*!
 * supa-sync.js — 設定（このブラウザの保存）を Supabase で端末どうし同期する共通の枠（リアルタイム更新つき）
 *
 * state-sync.js（GitHub の Gist で同期）と同じ考え方で、つなぎ先を Supabase にしたもの。
 *   - ログインはメールに届くリンクを押すだけ（端末ごとに鍵を貼らなくてよい）
 *   - アプリの名前で始まる保存（例 s3walk-state）を、Supabase の表 mathviz_state の「自分の行」に上げる（今あるプロジェクトに表を 1 つ足すだけで使える）
 *   - 開いた時（ログインした時）は、まず Supabase から読み込む。Supabase に設定があれば、手元と違う時はそちらに入れかえる（手元を上げるのは、読み込んだ後だけ）
 *   - リアルタイム更新：ほかの端末で変わったら、開いたままのこの画面にもすぐ届く（applyLive があれば読み直さずに反映）
 * 使い方・Supabase の準備（表と RLS の SQL）は同じフォルダの README.md・schema.sql を参照。
 *
 *   const sync = SupaSync.create({
 *     app: 's3walk', build: '20261025-0520',
 *     url: 'https://xxxx.supabase.co', anonKey: '…',   // 空なら欄で入れる（このブラウザに保存）
 *     also: ['vfx'],                                     // アプリの名前のほかに同期するキーの頭（共通の見た目の設定など）
 *     applyLive: (data, changed) => { … },               // ほかの端末の変更を、読み直さずに画面へ反映。false を返すと読み直す（その端末を触っていない時に）
 *   });
 *   sync.start();
 *   sync.mountUI(document.getElementById('supa-box'));
 *
 * supabase-js（v2）は CDN から必要になった時に読み込む。
 */
(function (global) {
    'use strict';

    const CDN = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.114.0/dist/umd/supabase.js';
    const ls = {
        get(k) { try { return localStorage.getItem(k) || ''; } catch (_) { return ''; } },
        set(k, v) { try { if (v === null || v === undefined || v === '') localStorage.removeItem(k); else localStorage.setItem(k, String(v)); } catch (_) {} },
        keys() { try { return Object.keys(localStorage); } catch (_) { return []; } },
    };
    // 同じサイトのアプリで共通（同期の対象には入らない）：つなぎ先・ログイン・この端末の印
    const SHARED = { URL: 'supaSyncUrl', ANON: 'supaSyncAnon', AUTH: 'supaSyncAuth', DEVICE: 'supaSyncDevice' };
    let clientP = null, clientKey = '';

    function loadLib() {
        if (global.supabase && global.supabase.createClient) return Promise.resolve(global.supabase);
        return new Promise((res, rej) => {
            const s = document.createElement('script'); s.src = CDN; s.async = true;
            s.onload = () => (global.supabase ? res(global.supabase) : rej(new Error('supabase-js を読み込めませんでした')));
            s.onerror = () => rej(new Error('supabase-js を読み込めませんでした（ネットにつながっていますか？）'));
            document.head.appendChild(s);
        });
    }
    function getClient(url, anon) {   // 同じページの中では 1 つだけ（アプリが 2 つ同期しても、ログインは共通）
        const key = url + '|' + anon;
        if (clientP && clientKey === key) return clientP;
        clientKey = key;
        clientP = loadLib().then(lib => lib.createClient(url, anon, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: SHARED.AUTH } }));
        return clientP;
    }
    function deviceId() {
        let d = ls.get(SHARED.DEVICE);
        if (!d) { d = 'd' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36); ls.set(SHARED.DEVICE, d); }
        return d;
    }

    function create(opts) {
        const o = Object.assign({
            app: 'app',
            build: '',                 // アプリの版の日付。新しい版を公開する時に書きかえる
            prefix: null,              // 同期するキーの頭（既定は app）
            exclude: [],               // 同期しないキー（端末ごとのもの）
            also: [],                  // アプリの名前のほかに同期するキーの頭（例 'vfx'＝共通の見た目の設定）
            url: '', anonKey: '',      // Supabase のプロジェクトの URL と公開用の鍵（anon key）。空なら欄で入れる
            table: 'mathviz_state',   // 表の名前（今あるプロジェクトの表とぶつからない名前）
            checkEverySec: 2,          // 変わったかを見る間隔（変わった時だけ上げる）
            applyLive: null,           // (data, changed) => ほかの端末の変更を読み直さずに反映（changed＝値が変わったキー）。false を返すか、無ければ読み直す
            live: null,                // ライブ同期（ぬるぬる）：{ get: () => 今の状態, set: 状態 => 画面へ反映, hz: 12 }。表に書かず Broadcast で端末どうし直接送る
            onStatus: null,
        }, opts || {});
        const CFG = global.SUPA_SYNC_CONFIG || {};   // supa-config.js（共通のつなぎ先）があればそれを使う
        if (!o.url && CFG.url) o.url = CFG.url;
        if (!o.anonKey && CFG.anonKey) o.anonKey = CFG.anonKey;
        const P = o.prefix || o.app;
        const K = { AUTO: P + 'SupaAuto', LOCAL_AT: P + 'SupaLocalAt', UP_AT: P + 'SupaUpAt' };
        const APPLIED = P + 'SupaApplied';   // sessionStorage：Supabase の状態に入れかえて読み直した直後
        const isSyncKey = k => (k.startsWith(P) || o.also.some(a => k.startsWith(a))) && !/Supa|Gist/.test(k) && !/token/i.test(k) && !o.exclude.includes(k);
        const url = () => (o.url || ls.get(SHARED.URL)).trim().replace(/\/+$/, '');
        const anon = () => (o.anonKey || ls.get(SHARED.ANON)).trim();
        const auto = () => ls.get(K.AUTO) !== '0';   // 既定は ON（ログインしていれば同期する）
        const DEV = deviceId();

        let client = null, user = null, chan = null, timer = null, busy = false, lastData = '', lastLocal = '', ui = null, lastStatus = ['', null], liveCount = 0;
        let ready = false;   // 開いた時（ログインした時）の読み込みが済んだか。済むまでは自動では上げない（読む前に手元で Supabase を上書きしないように）
        // ライブ同期：lchan（Broadcast）、送った・受け取った数、つながり具合。最後に触った端末が主（lead）、ほかはついていく（follow）
        let lchan = null, liveTimer = null, lastSent = '', liveSent = 0, liveRecv = 0, dbState = '', lchanState = '', followUntil = 0, leadUntil = 0;
        const liveOn = () => ls.get(P + 'SupaLive') !== '0';
        if (typeof document !== 'undefined') ['pointerdown', 'keydown', 'wheel', 'input'].forEach(ev => document.addEventListener(ev, () => { leadUntil = Date.now() + 1500; }, { capture: true, passive: true }));

        function status(msg, ok) {
            lastStatus = [msg, ok];
            if (o.onStatus) o.onStatus(msg, ok);
            if (ui && ui.st) { ui.st.textContent = msg; ui.st.style.color = ok === true ? '#6ee7b7' : ok === false ? '#fda4af' : '#94a3b8'; }
        }
        const errText = e => (e && (e.message || e.error_description || e.msg)) ? (e.message || e.error_description || e.msg) + (e.code ? '（' + e.code + '）' : '') : String(e);
        function data() {
            const d = {};
            ls.keys().filter(isSyncKey).sort().forEach(k => { d[k] = localStorage.getItem(k); });
            return d;
        }

        // ---------- つなぐ・ログイン ----------
        async function connect() {
            if (!url() || !anon()) { status('Supabase の URL と anon key を入れてください', false); renderUI(); return false; }
            try {
                client = await getClient(url(), anon());
                const { data: s } = await client.auth.getSession();
                user = s && s.session ? s.session.user : null;
                client.auth.onAuthStateChange((ev, session) => {
                    const was = user && user.id; user = session ? session.user : null;
                    if ((user && user.id) !== was) { renderUI(); if (user) afterLogin(); else stopLive(); }
                    else if (ev === 'USER_UPDATED') { renderUI(); if (user && user.email) status('ログインのメールアドレス：' + user.email, true); }   // メールアドレスを変えた時など
                });
                renderUI();
                return true;
            } catch (e) { status('つなげませんでした：' + errText(e), false); return false; }
        }
        async function sendLink(email) {
            if (!client && !(await connect())) return;
            const redirect = location.origin + location.pathname;
            const { error } = await client.auth.signInWithOtp({ email, options: { emailRedirectTo: redirect } });
            if (error) status('リンクを送れませんでした：' + errText(error), false);
            else status(email + ' にログインのリンクを送りました。メールのリンクを押すと、このページに戻ってログインします', true);
        }
        async function signInPw(email, password) {   // パスワードでログイン（メールは送らない）
            if (!client && !(await connect())) return;
            const { error } = await client.auth.signInWithPassword({ email, password });
            if (error) status('ログインできませんでした：' + (/invalid login credentials/i.test(error.message || '') ? 'メールアドレスかパスワードがちがいます（まだパスワードを決めていなければ、メールのリンクでログインした端末で先に決めてください）' : errText(error)), false);
            else { if (ui) ui.pw.value = ''; status('ログインしました', true); }
        }
        async function setPw(p1, p2) {   // ログイン中にパスワードを決める・変える
            if (!client || !user) { status('先にログインしてください', false); return; }
            if ((p1 || '').length < 6) { status('パスワードは 6 文字以上にしてください', false); return; }
            if (p1 !== p2) { status('2 つのパスワードがちがいます', false); return; }
            const { error } = await client.auth.updateUser({ password: p1 });
            if (error) { status('パスワードを決められませんでした：' + errText(error), false); return; }
            if (ui) { ui.pw1.value = ''; ui.pw2.value = ''; ui.pwset.open = false; }
            status('パスワードを決めました。ほかの端末では「パスワードでログイン」で、メールなしでログインできます', true);
        }
        async function setEmail(email) {   // ログイン中にメールアドレスを変える（新しいアドレスに確かめのメールが届き、リンクを押すと変わる）
            if (!client || !user) { status('先にログインしてください', false); return; }
            if (!/^\S+@\S+\.\S+$/.test(email)) { status('新しいメールアドレスを入れてください', false); return; }
            if (user.email && email.toLowerCase() === user.email.toLowerCase()) { status('今と同じアドレスです', false); return; }
            const { error } = await client.auth.updateUser({ email }, { emailRedirectTo: location.origin + location.pathname });
            if (error) { status('メールアドレスを変えられませんでした：' + errText(error), false); return; }
            if (ui) { ui.mail1.value = ''; ui.mailset.open = false; }
            status(email + ' に確かめのメールを送りました。メールのリンクを押すと変わります（設定によっては、今のアドレスにも確かめのメールが届くので、両方のリンクを押してください）', true);
        }
        async function signOut() { if (!client) return; await client.auth.signOut(); user = null; stopLive(); renderUI(); status('ログアウトしました'); }

        // ---------- 上げる・読む ----------
        function track() {   // 手元の設定が変わった時刻を記録（ログインしていなくても。開いた時に新しい方を決めるのに使う）
            const s = JSON.stringify(data());
            if (s !== lastLocal) { if (lastLocal) ls.set(K.LOCAL_AT, Date.now()); lastLocal = s; }
            return s;
        }
        async function upload(force) {
            const s = track();
            if (busy || !client || !user) return false;
            if (!ready && !force) return false;   // まだ Supabase を読んでいない：自動では上げない（「今すぐ上げる」は上げる）
            const d = JSON.parse(s);
            if (!+ls.get(K.LOCAL_AT)) ls.set(K.LOCAL_AT, Date.now());
            if (!force && s === lastData) return false;   // 上げた時（または Supabase の中身）から変わっていなければ上げない
            busy = true;
            try {
                const row = { user_id: user.id, app: o.app, data: d, build: o.build || null, saved_at: +ls.get(K.LOCAL_AT) || Date.now(), device: DEV };
                const { error } = await client.from(o.table).upsert(row, { onConflict: 'user_id,app' });
                if (error) throw error;
                lastData = s; ls.set(K.UP_AT, Date.now());
                status('上げました ' + new Date().toLocaleTimeString('ja-JP') + (chan ? '（リアルタイム ON）' : ''), true);
                return true;
            } catch (e) { status('上げられませんでした：' + errText(e), false); return false; }
            finally { busy = false; }
        }
        async function fetchRemote() {
            const { data: r, error } = await client.from(o.table).select('data,build,saved_at,device').eq('app', o.app).maybeSingle();
            if (error) throw error;
            return r;
        }
        function writeKeys(d) {   // Supabase の中身をこのブラウザに書く（無いキーは手元のまま）
            Object.keys(d || {}).forEach(k => { if (isSyncKey(k) && typeof d[k] === 'string') ls.set(k, d[k]); });
        }
        function applyRemote(r, live) {
            const d = r.data || {}, changed = Object.keys(d).filter(k => isSyncKey(k) && typeof d[k] === 'string' && ls.get(k) !== d[k]);
            writeKeys(d);
            ls.set(K.LOCAL_AT, r.saved_at || Date.now());
            lastData = lastLocal = JSON.stringify(data());
            if (live && !changed.length) return;
            if (live && o.applyLive) { try { if (o.applyLive(d, changed) !== false) { status('ほかの端末の変更を反映しました ' + new Date().toLocaleTimeString('ja-JP'), true); return; } } catch (e) { console.warn('supa-sync applyLive', e); } }
            try { sessionStorage.setItem(APPLIED, JSON.stringify({ build: r.build || '' })); } catch (_) {}
            if (live) softReload(); else location.reload();
        }
        // その場で反映できない変更：この端末を触っていない時（4 秒）に読み直す。1 分に 3 回までにして、端末どうしで読み直し合い続けないように
        let reloadWait = null;
        function softReload() {
            const RK = P + 'SupaReloads';
            let past = []; try { past = JSON.parse(sessionStorage.getItem(RK) || '[]').filter(t => Date.now() - t < 60000); } catch (_) {}
            if (past.length >= 3) { status('ほかの端末で変わった設定は、次に開いた時に反映します（読み直しが続いたので止めました）', false); return; }
            if (reloadWait) return;
            status('ほかの端末で変わった設定を反映するため、手を止めたら読み直します', true);
            reloadWait = setInterval(() => {
                if (Date.now() < leadUntil + 2500) return;
                clearInterval(reloadWait); reloadWait = null;
                try { sessionStorage.setItem(RK, JSON.stringify(past.concat(Date.now()))); } catch (_) {}
                location.reload();
            }, 500);
        }
        async function loadNow(ask) {
            if (!client || !user) { status('先にログインしてください', false); return; }
            try {
                const r = await fetchRemote();
                if (!r) { status('Supabase にまだこのアプリの設定がありません', false); return; }
                if (ask && !confirm('Supabase の設定（' + new Date(+r.saved_at).toLocaleString('ja-JP') + '）に入れかえますか？')) return;
                applyRemote(r, true);
            } catch (e) { status('読み込めませんでした：' + errText(e), false); }
        }

        // ---------- リアルタイム更新 ----------
        function startLive() {
            stopLive();
            if (!client || !user || !auto()) return;
            chan = client.channel('supa-sync-' + o.app + '-' + DEV)
                .on('postgres_changes', { event: '*', schema: 'public', table: o.table, filter: 'app=eq.' + o.app }, payload => {
                    const r = payload && payload.new;
                    if (!r || r.device === DEV || r.user_id !== user.id) return;   // 自分の変更のこだまは無視
                    if ((+r.saved_at || 0) <= (+ls.get(K.LOCAL_AT) || 0)) return;   // 手元の方が新しい
                    if (Date.now() < leadUntil + 3000) return;   // 今この端末をさわっている（主）：ついてきた端末が上げた少し前の状態に戻されないように
                    liveCount++; renderLive();
                    applyRemote(r, true);
                })
                .subscribe((st, err) => { dbState = st; renderLive(); if (st === 'SUBSCRIBED') status('同期しています（リアルタイム ON）', true); else if (st === 'CHANNEL_ERROR' || st === 'TIMED_OUT') { status('表のリアルタイムにつなげませんでした（' + st + (err && err.message ? '：' + err.message : '') + '）', false); console.warn('supa-sync realtime', st, err); } });
            startBroadcast();
        }
        // ---------- ライブ同期（ぬるぬる）：Broadcast で状態を 1 秒に hz 回、端末どうし直接送る ----------
        function startBroadcast() {
            if (!o.live || !client || !user || !liveOn()) return;
            const hz = Math.max(1, Math.min(30, o.live.hz || 12));
            lchan = client.channel('mvlive-' + o.app + '-' + user.id, { config: { broadcast: { self: false, ack: false } } })
                .on('broadcast', { event: 'state' }, msg => {
                    const p = msg && msg.payload;
                    if (!p || p.dev === DEV || !p.s) return;
                    if (Date.now() < leadUntil) return;   // 自分が今さわっている間は、ほかの端末の状態で上書きしない
                    liveRecv++; followUntil = Date.now() + 3000 / hz;
                    try { o.live.set(p.s); } catch (e) { console.warn('supa-sync live.set', e); }
                    try { lastSent = JSON.stringify(o.live.get()); } catch (_) {}   // 受け取った状態はこだまさせない
                    if (liveRecv % 10 === 1) renderLive();
                })
                .on('broadcast', { event: 'hello' }, msg => {   // あとから開いた端末が来た：ついていっている途中でなければ、今の状態をすぐ送る
                    const p = msg && msg.payload; if (!p || p.dev === DEV) return;
                    if (Date.now() >= followUntil) lastSent = '';
                })
                .subscribe((st, err) => {
                    lchanState = st; renderLive();
                    if (st === 'SUBSCRIBED') {   // 開いた時は自分の状態を送らない（動いている端末を古い状態で上書きしないため）。来たことだけ知らせて、今の状態をもらう
                        try { lastSent = JSON.stringify(o.live.get()); } catch (_) {}
                        lchan.send({ type: 'broadcast', event: 'hello', payload: { dev: DEV } });
                    }
                    if (st === 'CHANNEL_ERROR' || st === 'TIMED_OUT') console.warn('supa-sync broadcast', st, err);
                });
            clearInterval(liveTimer);
            liveTimer = setInterval(() => {
                if (!lchan || lchanState !== 'SUBSCRIBED') return;
                const now = Date.now(); if (now < followUntil && now >= leadUntil) return;   // ほかの端末についていっている間は送らない
                let sNow; try { sNow = JSON.stringify(o.live.get()); } catch (_) { return; }
                if (sNow === lastSent) return;
                lastSent = sNow; liveSent++;
                lchan.send({ type: 'broadcast', event: 'state', payload: { dev: DEV, s: JSON.parse(sNow) } });
                if (liveSent % 10 === 1) renderLive();
            }, 1000 / hz);
        }
        function stopLive() {
            if (chan && client) { try { client.removeChannel(chan); } catch (_) {} } chan = null; dbState = '';
            if (lchan && client) { try { client.removeChannel(lchan); } catch (_) {} } lchan = null; lchanState = ''; clearInterval(liveTimer); liveTimer = null;
            renderLive();
        }
        function renderLive() {   // つながり具合を欄に出す（どこで止まっているか分かるように）
            if (!ui || !ui.live) return;
            const w = st => st === 'SUBSCRIBED' ? 'つながっている' : st ? 'つながっていない（' + st + '）' : '—';
            ui.live.textContent = user ? '表の知らせ：' + w(dbState) + '（受け取り ' + liveCount + '）' + (o.live ? '　ライブ：' + (liveOn() ? w(lchanState) + '（送った ' + liveSent + '・受け取り ' + liveRecv + '）' : 'OFF') : '') : '';
            ui.live.style.color = (dbState === 'SUBSCRIBED' && (!o.live || !liveOn() || lchanState === 'SUBSCRIBED')) ? '#6ee7b7' : '#fbbf24';
        }

        // ---------- 開いた時・ログインした時 ----------
        async function afterLogin() {
            let applied = null;
            try { const a = sessionStorage.getItem(APPLIED); sessionStorage.removeItem(APPLIED); if (a) applied = JSON.parse(a); } catch (_) {}
            if (applied) { lastData = lastLocal = JSON.stringify(data()); ready = true; status('Supabase の設定を読み込みました', true); startLive(); return; }
            if (!auto()) { status('ログイン中（自動同期 OFF）'); return; }
            // まず読み込む：Supabase に設定があれば、手元と違う時はそちらに入れかえる（どちらが新しいかでは決めない。開いた時に手元で上書きしない）
            try {
                const r = await fetchRemote();
                if (r) {
                    const d = r.data || {}, diff = Object.keys(d).some(k => isSyncKey(k) && typeof d[k] === 'string' && ls.get(k) !== d[k]);
                    if (diff) { status('Supabase の設定を読み込みます…'); applyRemote(r, false); return; }
                    lastData = lastLocal = JSON.stringify(data()); ready = true;
                    status('同期しています（Supabase と同じ）', true);
                } else {   // Supabase にまだ無い：手元を初めて上げる
                    ready = true; await upload(true);
                }
            } catch (e) { status('Supabase を確かめられませんでした：' + errText(e) + '（読めるまで自動では上げません）', false); return; }
            startLive();
        }
        function schedule() {
            clearInterval(timer);
            timer = setInterval(() => { if (auto()) upload(false); else track(); }, Math.max(1, o.checkEverySec) * 1000);
        }

        // ---------- 同期の欄 ----------
        const CSS = `
.sp-box{font:12px/1.5 system-ui,-apple-system,'Hiragino Sans',sans-serif;color:#cbd5e1}
.sp-head{display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap}
.sp-title{font-weight:700;color:#6ee7b7}
.sp-st{font-size:11px;color:#94a3b8}
.sp-note{font-size:11px;color:#64748b;margin:4px 0 6px}
.sp-row{display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin-top:6px}
.sp-in{flex:1;min-width:150px;background:#0f172a;border:1px solid #334155;border-radius:6px;color:#e2e8f0;padding:5px 8px;font-size:12px}
.sp-in.mono{font-family:ui-monospace,Menlo,monospace}
.sp-btn{background:#1e293b;border:1px solid #475569;border-radius:7px;color:#cbd5e1;padding:5px 10px;font-size:12px;cursor:pointer;white-space:nowrap}
.sp-btn:hover{background:#334155}
.sp-btn:disabled{opacity:.4;cursor:not-allowed}
.sp-btn.on{background:rgba(6,95,70,.45);border-color:#34d399;color:#d1fae5;font-weight:700}
.sp-btn.go{background:rgba(5,150,105,.35);border-color:#34d399;color:#d1fae5;font-weight:700}
.sp-user{color:#e2e8f0}
.sp-cfg summary{cursor:pointer;color:#94a3b8;font-size:11px;margin-top:6px}`;
        function mountUI(el) {
            if (!el) return;
            if (!document.getElementById('sp-style')) { const st = document.createElement('style'); st.id = 'sp-style'; st.textContent = CSS; document.head.appendChild(st); }
            el.classList.add('sp-box');
            el.innerHTML = `
<div class="sp-head"><span class="sp-title">Supabase で同期（リアルタイム）</span><span class="sp-st"></span></div>
<div class="sp-note">メールのリンクでログインすると、設定を Supabase の自分だけの行に上げ、ほかの端末で開いている画面にもすぐ届きます。読み書きできるのは自分の行だけ（RLS）。</div>
<div data-k="out"><div class="sp-row"><input class="sp-in" data-k="email" type="email" autocomplete="username email" placeholder="メールアドレス"><input class="sp-in" data-k="pw" type="password" autocomplete="current-password" placeholder="パスワード（決めてあれば）"></div>
<div class="sp-row"><button class="sp-btn go" data-a="pwin">パスワードでログイン</button><button class="sp-btn" data-a="link">ログインのリンクをメールで送る</button></div>
<div class="sp-note">パスワードは、メールのリンクで一度ログインした端末で決めておけます。決めてあれば、ほかの端末ではメールを送らずにログインできます（メールは 1 時間に数通まで）。</div></div>
<div class="sp-row" data-k="in" hidden><span class="sp-user" data-k="who"></span><button class="sp-btn" data-a="auto"></button><button class="sp-btn" data-a="liveon" hidden></button><button class="sp-btn go" data-a="now">今すぐ上げる</button><button class="sp-btn" data-a="load">Supabase から読み込む</button><button class="sp-btn" data-a="out">ログアウト</button></div>
<div class="sp-note" data-k="live"></div>
<details class="sp-cfg" data-k="pwset" hidden><summary>パスワードを決める・変える（ほかの端末でメールなしでログインできるように）</summary>
<div class="sp-row"><input class="sp-in" data-k="pw1" type="password" autocomplete="new-password" placeholder="新しいパスワード（6 文字以上）"><input class="sp-in" data-k="pw2" type="password" autocomplete="new-password" placeholder="もう一度"><button class="sp-btn go" data-a="pwset">決める</button></div></details>
<details class="sp-cfg" data-k="mailset" hidden><summary>メールアドレスを変える</summary>
<div class="sp-note">新しいアドレスに確かめのメールが届き、リンクを押すと変わります（設定によっては今のアドレスにも届くので両方押す）。Supabase の標準のメールは、プロジェクトのメンバー（Supabase のアカウント）のアドレスにしか届きません。変えた後も、設定とパスワードはそのままです。</div>
<div class="sp-row"><input class="sp-in" data-k="mail1" type="email" autocomplete="email" placeholder="新しいメールアドレス"><button class="sp-btn go" data-a="mailset">確かめのメールを送る</button></div></details>
<details class="sp-cfg"><summary>つなぎ先（Supabase の URL と anon key）</summary>
<div class="sp-row"><input class="sp-in mono" data-k="url" type="text" spellcheck="false" placeholder="https://xxxx.supabase.co"></div>
<div class="sp-row"><input class="sp-in mono" data-k="anon" type="text" spellcheck="false" placeholder="anon key（公開用の鍵）"><button class="sp-btn" data-a="cfg">保存してつなぐ</button></div></details>`;
            const q = s => el.querySelector(s);
            ui = { el, st: q('.sp-st'), email: q('[data-k=email]'), out: q('[data-k=out]'), inn: q('[data-k=in]'), who: q('[data-k=who]'), auto: q('[data-a=auto]'),
                now: q('[data-a=now]'), load: q('[data-a=load]'), url: q('[data-k=url]'), anon: q('[data-k=anon]'), cfg: q('details.sp-cfg:not([data-k])'),
                pw: q('[data-k=pw]'), pwset: q('[data-k=pwset]'), pw1: q('[data-k=pw1]'), pw2: q('[data-k=pw2]'), mailset: q('[data-k=mailset]'), mail1: q('[data-k=mail1]'), live: q('[data-k=live]'), liveon: q('[data-a=liveon]') };
            q('[data-a=link]').onclick = () => { const e = ui.email.value.trim(); if (!/^\S+@\S+\.\S+$/.test(e)) { status('メールアドレスを入れてください', false); return; } sendLink(e); };
            q('[data-a=out]').onclick = signOut;
            q('[data-a=pwin]').onclick = () => { const e = ui.email.value.trim(), p = ui.pw.value; if (!/^\S+@\S+\.\S+$/.test(e)) { status('メールアドレスを入れてください', false); return; } if (!p) { status('パスワードを入れてください', false); return; } signInPw(e, p); };
            ui.pw.onkeydown = ev => { if (ev.key === 'Enter') q('[data-a=pwin]').click(); };
            q('[data-a=pwset]').onclick = () => setPw(ui.pw1.value, ui.pw2.value);
            q('[data-a=mailset]').onclick = () => setEmail(ui.mail1.value.trim());
            ui.liveon.onclick = () => { ls.set(P + 'SupaLive', liveOn() ? '0' : null); renderUI(); if (lchan || chan) { stopLive(); startLive(); } };
            ui.auto.onclick = () => { ls.set(K.AUTO, auto() ? '0' : null); renderUI(); if (auto()) afterLogin(); else { stopLive(); status('自動同期を止めました'); } };
            ui.now.onclick = () => upload(true);
            ui.load.onclick = () => loadNow(true);
            q('[data-a=cfg]').onclick = async () => { ls.set(SHARED.URL, ui.url.value.trim()); ls.set(SHARED.ANON, ui.anon.value.trim()); clientP = null; if (await connect()) { status('つなぎ先を保存しました', true); if (user) afterLogin(); } };
            renderUI();
            if (lastStatus[0]) status(lastStatus[0], lastStatus[1]);
        }
        function renderUI() {
            if (!ui) return;
            const a = auto();
            ui.out.hidden = !!user; ui.inn.hidden = !user; ui.pwset.hidden = !user; ui.mailset.hidden = !user;
            ui.liveon.hidden = !o.live; ui.liveon.textContent = 'ぬるぬる同期: ' + (liveOn() ? 'ON' : 'OFF'); ui.liveon.classList.toggle('on', liveOn()); renderLive();
            ui.who.textContent = user ? (user.email || 'ログイン中') + '　' : '';
            ui.auto.textContent = '自動同期: ' + (a ? 'ON' : 'OFF'); ui.auto.classList.toggle('on', a);
            if (document.activeElement !== ui.url) ui.url.value = url();
            if (document.activeElement !== ui.anon) ui.anon.value = anon();
            ui.cfg.open = !url() || !anon();
            ui.url.disabled = !!o.url; ui.anon.disabled = !!o.anonKey;   // アプリに書いてある時は変えない
        }

        // ---------- 開始 ----------
        async function start() {
            lastLocal = JSON.stringify(data());   // 開いた時の手元の設定（ここからの変更を記録する）
            schedule();
            document.addEventListener('visibilitychange', () => { if (document.hidden && auto()) upload(false); });
            if (!url() || !anon()) { status('つなぎ先（URL と anon key）が未設定です'); renderUI(); return; }
            if (await connect()) { if (user) afterLogin(); else status('ログインしていません（メールのリンクでログイン）'); }
        }

        return { start, mountUI, uploadNow: () => upload(true), loadNow, status, get user() { return user; }, get liveCount() { return liveCount; }, get liveInfo() { return { dbState, lchanState, liveSent, liveRecv }; }, device: DEV };
    }

    // 0.1.1：supa-config.js（共通のつなぎ先）を読む、supabase-js 2.114.0（新しい publishable key に対応）
    // 0.2.0：パスワードでログイン（メールを送らない）・ログイン中にパスワードを決める
    // 0.3.0：ログイン中にメールアドレスを変える
    // 0.4.0：ライブ同期（Broadcast で位置・向きなども 1 秒に十数回）、つながり具合の表示
    // 0.6.0：開いた時（ログインした時）はまず読み込む。読み込みが済むまで自動では上げない（2 秒ごとの確かめが読む前に手元で上書きしていた）。どちらが新しいかでは決めない
    // 0.5.0：画面まるごと同期のために、also（アプリの名前のほかのキーの頭）、applyLive に changed（変わったキー）と false で読み直し（触っていない時・1 分に 3 回まで）
    global.SupaSync = { create, version: '0.6.0' };
})(typeof window !== 'undefined' ? window : this);
