/*!
 * supa-sync.js — 設定（このブラウザの保存）を Supabase で端末どうし同期する共通の枠（リアルタイム更新つき）
 *
 * state-sync.js（GitHub の Gist で同期）と同じ考え方で、つなぎ先を Supabase にしたもの。
 *   - ログインはメールに届くリンクを押すだけ（端末ごとに鍵を貼らなくてよい）
 *   - アプリの名前で始まる保存（例 s3walk-state）を、Supabase の表 mathviz_state の「自分の行」に上げる（今あるプロジェクトに表を 1 つ足すだけで使える）
 *   - 開いた時、Supabase の方が新しければそちらに合わせる
 *   - リアルタイム更新：ほかの端末で変わったら、開いたままのこの画面にもすぐ届く（applyLive があれば読み直さずに反映）
 * 使い方・Supabase の準備（表と RLS の SQL）は同じフォルダの README.md・schema.sql を参照。
 *
 *   const sync = SupaSync.create({
 *     app: 's3walk', build: '20261025-0520',
 *     url: 'https://xxxx.supabase.co', anonKey: '…',   // 空なら欄で入れる（このブラウザに保存）
 *     applyLive: data => { … },                          // ほかの端末の変更を、読み直さずに画面へ反映（無ければ読み直す）
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
            exclude: [],               // 同期しないキー（端末ごとのもの。例：欄の分離の並び）
            url: '', anonKey: '',      // Supabase のプロジェクトの URL と公開用の鍵（anon key）。空なら欄で入れる
            table: 'mathviz_state',   // 表の名前（今あるプロジェクトの表とぶつからない名前）
            checkEverySec: 2,          // 変わったかを見る間隔（変わった時だけ上げる）
            applyLive: null,           // (data) => ほかの端末の変更を読み直さずに反映。無ければ読み直す
            onStatus: null,
        }, opts || {});
        const CFG = global.SUPA_SYNC_CONFIG || {};   // supa-config.js（共通のつなぎ先）があればそれを使う
        if (!o.url && CFG.url) o.url = CFG.url;
        if (!o.anonKey && CFG.anonKey) o.anonKey = CFG.anonKey;
        const P = o.prefix || o.app;
        const K = { AUTO: P + 'SupaAuto', LOCAL_AT: P + 'SupaLocalAt', UP_AT: P + 'SupaUpAt' };
        const APPLIED = P + 'SupaApplied';   // sessionStorage：Supabase の状態に入れかえて読み直した直後
        const isSyncKey = k => k.startsWith(P) && !k.startsWith(P + 'Supa') && !k.startsWith(P + 'Gist') && !/token/i.test(k) && !o.exclude.includes(k);
        const url = () => (o.url || ls.get(SHARED.URL)).trim().replace(/\/+$/, '');
        const anon = () => (o.anonKey || ls.get(SHARED.ANON)).trim();
        const auto = () => ls.get(K.AUTO) !== '0';   // 既定は ON（ログインしていれば同期する）
        const DEV = deviceId();

        let client = null, user = null, chan = null, timer = null, busy = false, lastData = '', lastLocal = '', ui = null, lastStatus = ['', null], liveCount = 0;

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
            writeKeys(r.data);
            ls.set(K.LOCAL_AT, r.saved_at || Date.now());
            lastData = lastLocal = JSON.stringify(data());
            if (live && o.applyLive) { try { o.applyLive(r.data); status('ほかの端末の変更を反映しました ' + new Date().toLocaleTimeString('ja-JP'), true); return; } catch (e) { console.warn('supa-sync applyLive', e); } }
            try { sessionStorage.setItem(APPLIED, JSON.stringify({ build: r.build || '' })); } catch (_) {}
            location.reload();
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
                    liveCount++;
                    applyRemote(r, true);
                })
                .subscribe(st => { if (st === 'SUBSCRIBED') status('同期しています（リアルタイム ON）', true); else if (st === 'CHANNEL_ERROR' || st === 'TIMED_OUT') status('リアルタイムにつなげませんでした（' + st + '）。表を supabase_realtime に足しましたか？', false); });
        }
        function stopLive() { if (chan && client) { try { client.removeChannel(chan); } catch (_) {} } chan = null; }

        // ---------- 開いた時・ログインした時 ----------
        async function afterLogin() {
            let applied = null;
            try { const a = sessionStorage.getItem(APPLIED); sessionStorage.removeItem(APPLIED); if (a) applied = JSON.parse(a); } catch (_) {}
            if (applied) { lastData = lastLocal = JSON.stringify(data()); status('Supabase の新しい設定に合わせました', true); startLive(); return; }
            if (!auto()) { status('ログイン中（自動同期 OFF）'); return; }
            try {
                const r = await fetchRemote();
                if (r && (+r.saved_at || 0) > (+ls.get(K.LOCAL_AT) || 0) + 2000) { status('Supabase の方が新しいので合わせます…'); applyRemote(r, false); return; }
                lastData = r ? JSON.stringify(r.data) : '';
                await upload(false);   // 手元の方が新しければ上げる
                status('同期しています', true);
            } catch (e) { status('Supabase を確かめられませんでした：' + errText(e), false); }
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
<div class="sp-row" data-k="out"><input class="sp-in" data-k="email" type="email" autocomplete="email" placeholder="メールアドレス"><button class="sp-btn go" data-a="link">ログインのリンクを送る</button></div>
<div class="sp-row" data-k="in" hidden><span class="sp-user" data-k="who"></span><button class="sp-btn" data-a="auto"></button><button class="sp-btn go" data-a="now">今すぐ上げる</button><button class="sp-btn" data-a="load">Supabase から読み込む</button><button class="sp-btn" data-a="out">ログアウト</button></div>
<details class="sp-cfg"><summary>つなぎ先（Supabase の URL と anon key）</summary>
<div class="sp-row"><input class="sp-in mono" data-k="url" type="text" spellcheck="false" placeholder="https://xxxx.supabase.co"></div>
<div class="sp-row"><input class="sp-in mono" data-k="anon" type="text" spellcheck="false" placeholder="anon key（公開用の鍵）"><button class="sp-btn" data-a="cfg">保存してつなぐ</button></div></details>`;
            const q = s => el.querySelector(s);
            ui = { el, st: q('.sp-st'), email: q('[data-k=email]'), out: q('[data-k=out]'), inn: q('[data-k=in]'), who: q('[data-k=who]'), auto: q('[data-a=auto]'),
                now: q('[data-a=now]'), load: q('[data-a=load]'), url: q('[data-k=url]'), anon: q('[data-k=anon]'), cfg: q('.sp-cfg') };
            q('[data-a=link]').onclick = () => { const e = ui.email.value.trim(); if (!/^\S+@\S+\.\S+$/.test(e)) { status('メールアドレスを入れてください', false); return; } sendLink(e); };
            q('[data-a=out]').onclick = signOut;
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
            ui.out.hidden = !!user; ui.inn.hidden = !user;
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

        return { start, mountUI, uploadNow: () => upload(true), loadNow, status, get user() { return user; }, get liveCount() { return liveCount; }, device: DEV };
    }

    global.SupaSync = { create, version: '0.1.1' };   // 0.1.1：supa-config.js（共通のつなぎ先）を読む、supabase-js 2.114.0（新しい publishable key に対応）
})(typeof window !== 'undefined' ? window : this);
