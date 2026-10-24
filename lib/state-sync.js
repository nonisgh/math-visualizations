/*!
 * state-sync.js — 画面の状態の自動保存＋シークレット Gist との同期（共通の枠）
 *
 * 次元おりがみ（hypercube.html）に入れた仕組みを、どのアプリでも使えるように取り出したもの。
 * 使い方・仕様は同じフォルダの README.md を参照。
 *
 *   const sync = StateSync.create({
 *     app: 'ndim',                         // アプリの名前（保存キーの頭・Gist の中のファイル名に使う）
 *     snapshot: () => ({ ... }),           // 今の画面の状態を返す（JSON にできる値だけ）
 *     restore: s => { ... },               // 保存した状態を画面に戻す
 *   });
 *   sync.start();                          // 前回の画面に戻す → 定期保存 → Gist 同期の準備
 *   sync.mountUI(document.getElementById('sync-box'));   // 同期の欄（鍵・ID・自動同期…）を作る
 *
 * 依存なし（素の JavaScript）。localStorage・sessionStorage・fetch を使う。
 */
(function (global) {
    'use strict';

    const API = 'https://api.github.com/gists';
    const ls = {
        get(k) { try { return localStorage.getItem(k) || ''; } catch (_) { return ''; } },
        set(k, v) { try { if (v === null || v === undefined || v === '') localStorage.removeItem(k); else localStorage.setItem(k, String(v)); } catch (_) {} },
        keys() { try { return Object.keys(localStorage); } catch (_) { return []; } },
    };

    function create(opts) {
        const o = Object.assign({
            app: 'app',
            build: '',                    // アプリの版の日付（例 '20261020-0740'）。新しい版を公開する時に書きかえる
            prefix: null,                 // 同期するキーの頭（既定は app）
            sessionKey: null,             // 画面の状態を入れるキー（既定は prefix + 'Session'）
            snapshot: () => ({}),
            restore: () => {},
            saveEverySec: 3,              // 画面の状態をこのブラウザに保存する間隔（変わった時だけ書く）
            exclude: [],                  // 同期しないキー（鍵や同期の記録は自動で除く）
            tokenKey: 'gistSyncToken',    // 鍵：同じサイトのアプリで 1 本を共有
            idKey: 'gistSyncId',          // Gist ID：同じサイトのアプリで 1 つの Gist を共有（ファイルはアプリごと）
            file: null,                   // Gist の中のファイル名（既定は app + '-state.json'）
            description: null,            // 新しく作る Gist の説明
            defaultEverySec: 60,          // 自動同期の間隔の既定（10 / 30 / 60 / 300 から選べる）
            minEverySec: 10,              // いちばん短い間隔。GitHub の書き込み上限（目安 1 時間 500 回）に収まるよう 10 秒（＝最大 360 回）
            onStatus: null,               // (文字, ok) 状態の表示を自分で出したい時
        }, opts || {});
        const P = o.prefix || o.app;
        const SESSION = o.sessionKey || (P + 'Session');
        const FILE = o.file || (o.app + '-state.json');
        const K = {   // このアプリだけの同期の記録（同期の対象からは外す）
            AUTO: P + 'GistAuto', EVERY: P + 'GistEvery', LOCAL_AT: P + 'GistLocalAt', UP_AT: P + 'GistUpAt',
        };
        const APPLIED = P + 'GistApplied';   // sessionStorage：Gist の状態に入れかえて読み直した直後
        const isSyncKey = k => k.startsWith(P) && !k.startsWith(P + 'Gist') && !/token/i.test(k) && !o.exclude.includes(k) && k !== o.tokenKey && k !== o.idKey;

        let lastSession = '', lastData = '', saveTimer = null, gistTimer = null, busy = false, skip = false, ui = null;
        let pausedUntil = 0;   // GitHub の上限に当たった時は、しばらく自動で上げるのを休む

        // ---------- 画面の状態をこのブラウザに ----------
        function saveNow() {
            if (skip) return;
            try {
                const j = JSON.stringify({ v: 1, at: Date.now(), build: o.build, s: o.snapshot() });
                const body = j.replace(/"at":\d+,/, '');   // 時刻を除いて比べる
                if (body === lastSession) return;
                localStorage.setItem(SESSION, j); lastSession = body;
            } catch (e) { console.warn('[state-sync] 保存できませんでした', e); }
        }
        function restoreNow() {
            let d = null;
            try { d = JSON.parse(localStorage.getItem(SESSION) || 'null'); } catch (_) { d = null; }
            if (d && d.v === 1 && d.s !== undefined) {
                try { o.restore(d.s); } catch (e) { console.warn('[state-sync] 前回の画面を戻せませんでした', e); }
            }
            try { lastSession = JSON.stringify({ v: 1, at: 0, s: o.snapshot() }).replace(/"at":\d+,/, ''); } catch (_) {}
        }

        // ---------- Gist ----------
        let lastStatus = ['', undefined];   // 欄を作る前に出した知らせも、欄を作った時に出す
        const status = (msg, ok) => {
            lastStatus = [msg, ok];
            if (o.onStatus) o.onStatus(msg, ok);
            if (ui && ui.st) { ui.st.textContent = msg; ui.st.style.color = ok === true ? '#6ee7b7' : ok === false ? '#fda4af' : '#94a3b8'; }
        };
        const token = () => ls.get(o.tokenKey), gistId = () => ls.get(o.idKey);
        const auto = () => ls.get(K.AUTO) === '1';
        const everySec = () => Math.max(o.minEverySec, +ls.get(K.EVERY) || o.defaultEverySec);
        const headers = json => Object.assign(json ? { 'Content-Type': 'application/json' } : {}, {
            'Authorization': 'Bearer ' + token(), 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28',
        });
        // 書き込みの上限に当たった（429、または 403 で待ち時間・残り 0 が付いている）
        const limited = r => r.status === 429 || (r.status === 403 && (r.headers.get('retry-after') || r.headers.get('x-ratelimit-remaining') === '0'));
        const explain = r => limited(r) ? 'GitHub の書き込み上限に当たりました（しばらく休んでから続けます）' : r.status === 401 ? '鍵が無効です（期限切れ・貼り間違い）' : r.status === 403 ? '鍵に gist の権限がありません'
            : r.status === 404 ? 'Gist が見つかりません（ID 違い・別のアカウント）' : 'HTTP ' + r.status;
        // 知らせに、GitHub が返した理由（番号・文・残り回数・待つ時間）も付ける（「上限」と出た時に本当の理由が分かるように）
        async function explainFull(r) {
            let msg = ''; try { const t = await r.text(); try { msg = (JSON.parse(t) || {}).message || ''; } catch (_) { msg = t.slice(0, 120); } } catch (_) {}
            const rem = r.headers.get('x-ratelimit-remaining'), ra = +r.headers.get('retry-after') || 0, rs = +r.headers.get('x-ratelimit-reset') || 0;
            const waitMin = ra ? Math.ceil(ra / 60) : (rem === '0' && rs ? Math.max(1, Math.ceil((rs * 1000 - Date.now()) / 60000)) : 0);
            return explain(r) + '（HTTP ' + r.status + (msg ? '：' + msg : '') + (rem !== null && rem !== undefined ? '、残り ' + rem + ' 回' : '') + (waitMin ? '、約 ' + waitMin + ' 分待つ' : '') + '）';
        }
        function data() {   // 同期する中身（キー順にそろえて、変わったかを文字列で比べられるように）
            const d = {};
            ls.keys().filter(isSyncKey).sort().forEach(k => { d[k] = localStorage.getItem(k); });
            return d;
        }
        async function upload(force) {
            if (busy || !token()) return false;
            saveNow();
            const d = data(), s = JSON.stringify(d);
            if (s !== lastData) ls.set(K.LOCAL_AT, Date.now());
            if (!force && s === lastData && ls.get(K.UP_AT)) return false;   // 変わっていなければ上げない
            if (!force && Date.now() < pausedUntil) return false;            // 上限に当たって休んでいる間
            busy = true;
            try {
                const content = JSON.stringify({ app: o.app, kind: 'state', v: 1, build: o.build, savedAt: +ls.get(K.LOCAL_AT) || Date.now(), data: d }, null, 1);
                const files = { [FILE]: { content } }, id = gistId();
                const r = id
                    ? await fetch(API + '/' + encodeURIComponent(id), { method: 'PATCH', headers: headers(true), body: JSON.stringify({ files }) })
                    : await fetch(API, { method: 'POST', headers: headers(true), body: JSON.stringify({ public: false, description: o.description || (o.app + '：画面の状態と設定（自動同期）'), files }) });
                if (!r.ok) {
                    if (limited(r)) {
                        const wait = Math.max(60, +r.headers.get('retry-after') || 0, ((+r.headers.get('x-ratelimit-reset') || 0) * 1000 - Date.now()) / 1000);
                        pausedUntil = Date.now() + Math.min(3600, wait) * 1000;
                    }
                    throw new Error(await explainFull(r));
                }
                const j = await r.json();
                if (!id && j && j.id) ls.set(o.idKey, j.id);
                lastData = s; ls.set(K.UP_AT, Date.now());
                status('上げました ' + new Date().toLocaleTimeString('ja-JP'), true);
                renderUI();
                return true;
            } catch (e) { status('上げられませんでした：' + (e && e.message ? e.message : e), false); return false; }
            finally { busy = false; }
        }
        async function fetchRemote() {   // このアプリのファイル（無ければ null）
            if (!gistId() || !token()) return null;
            const r = await fetch(API + '/' + encodeURIComponent(gistId()), { headers: headers(false), cache: 'no-store' });
            if (!r.ok) throw new Error(await explainFull(r));
            const g = await r.json(), f = g && g.files && g.files[FILE];
            if (!f) return null;
            let txt = f.content;
            if (f.truncated && f.raw_url) txt = await (await fetch(f.raw_url, { cache: 'no-store' })).text();
            const d = JSON.parse(txt);
            if (!d || d.app !== o.app || !d.data || typeof d.data !== 'object') throw new Error('形式が違います');
            return d;
        }
        // 画面の状態をまぜる：Gist 側にある項目は Gist の値、無い項目（古い版から上げた時など）は手元の値を残す（中の入れ物も 1 段だけ）
        const plain = x => x && typeof x === 'object' && !Array.isArray(x);
        const merge1 = (a, b) => {
            if (!plain(a) || !plain(b)) return b;
            const out = Object.assign({}, a, b);
            Object.keys(b).forEach(k => { if (plain(a[k]) && plain(b[k])) out[k] = Object.assign({}, a[k], b[k]); });
            return out;
        };
        function mergeSession(localStr, remoteStr) {
            try {
                const a = JSON.parse(localStr || 'null'), b = JSON.parse(remoteStr || 'null');
                if (!plain(a) || !plain(b) || !plain(a.s) || !plain(b.s)) return remoteStr;
                return JSON.stringify(Object.assign({}, b, { s: merge1(a.s, b.s) }));
            } catch (_) { return remoteStr; }
        }
        // Gist に上げた端末のアプリの版と、このページの版の違いを、ひとことで
        function buildNote(b) {
            if (!o.build) return '';
            if (!b) return '（版の記録が無い古い版から上げた状態なので、足りない項目は手元の値を残しました）';
            if (b < o.build) return '（古い版 ' + b + ' から上げた状態なので、足りない項目は手元の値を残しました）';
            if (b > o.build) return '（Gist は新しい版 ' + b + ' から上げた状態です。このページを読み直すと新しい版になります）';
            return '';
        }
        function applyRemote(d) {   // Gist の状態をこのブラウザに入れて、読み直す（Gist に無いキーは書きかえない＝手元のまま）
            Object.keys(d.data).forEach(k => {
                if (!isSyncKey(k) || typeof d.data[k] !== 'string') return;
                ls.set(k, k === SESSION ? mergeSession(ls.get(k), d.data[k]) : d.data[k]);
            });
            ls.set(K.LOCAL_AT, d.savedAt || Date.now());
            try { sessionStorage.setItem(APPLIED, JSON.stringify({ build: d.build || '' })); } catch (_) {}
            skip = true;   // 読み直すまで、今の画面で上書きしない
            location.reload();
        }
        async function loadFromGist(ask = true) {
            try {
                status('Gist から読み込み中…');
                const d = await fetchRemote();
                if (!d) { status('Gist にまだこのアプリの状態がありません', false); return; }
                if (ask && !confirm('Gist の状態（' + new Date(d.savedAt).toLocaleString('ja-JP') + '）に入れかえて、読み直しますか？')) { status(''); return; }
                applyRemote(d);
            } catch (e) { status('読み込めませんでした：' + (e && e.message ? e.message : e), false); }
        }
        function schedule() {
            clearInterval(gistTimer); gistTimer = null;
            if (!auto() || !token()) return;
            gistTimer = setInterval(() => upload(false), everySec() * 1000);
        }
        async function checkOnOpen() {   // 開いた時：Gist の方が新しければ、そちらに合わせる（読み直しは 1 回だけ）
            let applied = null;
            try { const a = sessionStorage.getItem(APPLIED); sessionStorage.removeItem(APPLIED); if (a) applied = a === '1' ? {} : JSON.parse(a); } catch (_) {}
            if (applied) { lastData = JSON.stringify(data()); status('Gist の新しい状態に合わせました' + buildNote(applied.build), true); return; }
            if (!auto() || !token() || !gistId()) return;
            try {
                const d = await fetchRemote();
                if (d && d.savedAt > (+ls.get(K.LOCAL_AT) || 0) + 2000) { status('Gist の方が新しいので合わせます…'); applyRemote(d); return; }
                lastData = d ? JSON.stringify(d.data) : '';
                status('同期しています（' + everySec() + ' 秒ごと）' + (d && d.build && o.build && d.build > o.build ? buildNote(d.build) : ''), true);
            } catch (e) { status('Gist を確かめられませんでした：' + (e && e.message ? e.message : e), false); }
        }

        // ---------- 同期の欄 ----------
        const CSS = `
.ss-box{font:12px/1.5 system-ui,-apple-system,'Hiragino Sans',sans-serif;color:#cbd5e1}
.ss-head{display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap}
.ss-title{font-weight:700;color:#f5d0fe}
.ss-st{font-size:11px;color:#94a3b8}
.ss-note{font-size:11px;color:#64748b;margin:4px 0 6px}
.ss-note a{color:#7dd3fc}
.ss-row{display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin-top:6px}
.ss-in{flex:1;min-width:150px;background:#0f172a;border:1px solid #334155;border-radius:6px;color:#e2e8f0;padding:5px 8px;font-size:12px}
.ss-in.mono{font-family:ui-monospace,Menlo,monospace}
.ss-btn{background:#1e293b;border:1px solid #475569;border-radius:7px;color:#cbd5e1;padding:5px 10px;font-size:12px;cursor:pointer;white-space:nowrap}
.ss-btn:hover{background:#334155}
.ss-btn:disabled{opacity:.4;cursor:not-allowed}
.ss-btn.on{background:rgba(112,26,117,.45);border-color:#e879f9;color:#fae8ff;font-weight:700}
.ss-btn.go{background:rgba(5,150,105,.35);border-color:#34d399;color:#d1fae5;font-weight:700}
.ss-sel{background:#0f172a;border:1px solid #334155;border-radius:6px;color:#e2e8f0;padding:4px 6px;font-size:12px}
.ss-link{color:#7dd3fc;font-size:12px}`;
        function mountUI(el) {
            if (!el) return;
            if (!document.getElementById('ss-style')) { const st = document.createElement('style'); st.id = 'ss-style'; st.textContent = CSS; document.head.appendChild(st); }
            el.classList.add('ss-box');
            el.innerHTML = `
<div class="ss-head"><span class="ss-title">画面の状態を Gist に自動同期</span><span class="ss-st"></span></div>
<div class="ss-note">画面の状態と設定を、シークレット Gist（URL を知っている人だけが見られ、一覧には出ない）へ定期的に上げます。別の端末でも同じ鍵と Gist ID を入れておくと、開いた時に新しい方の状態にそろいます。鍵は <b>gist の権限だけ</b>のもの（<a href="https://github.com/settings/tokens/new?scopes=gist&amp;description=gist-state-sync" target="_blank" rel="noopener">ここで作れます</a>）。鍵はこのブラウザにだけ保存され、Gist には入りません。</div>
<div class="ss-row"><input class="ss-in" data-k="token" type="password" autocomplete="off" spellcheck="false"><button class="ss-btn" data-a="tokenSave">鍵を保存</button><button class="ss-btn" data-a="tokenClear">鍵を消す</button></div>
<div class="ss-row"><input class="ss-in mono" data-k="id" type="text" autocomplete="off" spellcheck="false" placeholder="Gist ID（空なら最初の同期で新しく作る）"><button class="ss-btn" data-a="idSave">ID を保存</button><a class="ss-link" data-k="open" target="_blank" rel="noopener" hidden>Gist を開く ↗</a></div>
<div class="ss-row"><button class="ss-btn" data-a="auto"></button><select class="ss-sel" data-k="every"><option value="10">10 秒ごと</option><option value="30">30 秒ごと</option><option value="60">1 分ごと</option><option value="300">5 分ごと</option></select><button class="ss-btn go" data-a="now">今すぐ上げる</button><button class="ss-btn" data-a="load">Gist から読み込む</button></div>`;
            const q = s => el.querySelector(s);
            ui = { el, st: q('.ss-st'), token: q('[data-k=token]'), id: q('[data-k=id]'), open: q('[data-k=open]'), every: q('[data-k=every]'),
                auto: q('[data-a=auto]'), now: q('[data-a=now]'), load: q('[data-a=load]'), clear: q('[data-a=tokenClear]') };
            q('[data-a=tokenSave]').onclick = () => {
                const v = ui.token.value.trim();
                if (!v) { status('鍵を貼り付けてから押してください', false); return; }
                ls.set(o.tokenKey, v); renderUI(); schedule(); status('鍵をこのブラウザに保存しました', true);
            };
            ui.clear.onclick = () => { ls.set(o.tokenKey, null); renderUI(); schedule(); status('鍵を消しました'); };
            q('[data-a=idSave]').onclick = () => {
                const v = ui.id.value.trim().replace(/^https?:\/\/gist\.github\.com\/(?:[^/]+\/)?/, '').replace(/[^0-9a-fA-F]/g, '');
                ls.set(o.idKey, v); renderUI(); status(v ? 'Gist ID を保存しました' : 'Gist ID を消しました（次の同期で新しく作ります）', true);
            };
            ui.auto.onclick = () => {
                const on = !auto();
                ls.set(K.AUTO, on ? '1' : null); renderUI(); schedule();
                if (on) { if (token()) upload(true); else status('先に鍵を保存してください', false); }
            };
            ui.every.onchange = e => { ls.set(K.EVERY, e.target.value); schedule(); };
            ui.now.onclick = () => upload(true);
            ui.load.onclick = () => loadFromGist(true);
            renderUI();
            if (lastStatus[0]) status(lastStatus[0], lastStatus[1]);
        }
        function renderUI() {
            if (!ui) return;
            const t = token(), id = gistId(), a = auto();
            ui.token.value = ''; ui.token.placeholder = t ? '鍵は保存済み（貼り直すと上書き）' : 'ghp_…（gist だけの鍵）を貼り付け';
            ui.clear.style.display = t ? '' : 'none';
            if (document.activeElement !== ui.id) ui.id.value = id;
            ui.open.hidden = !id; if (id) ui.open.href = 'https://gist.github.com/' + encodeURIComponent(id);
            ui.auto.textContent = '自動同期: ' + (a ? 'ON' : 'OFF'); ui.auto.classList.toggle('on', a);
            ui.every.value = String([10, 30, 60, 300].includes(everySec()) ? everySec() : 60);
            ui.now.disabled = !t; ui.load.disabled = !t || !id;
        }

        // ---------- 開始 ----------
        function start() {
            restoreNow();
            clearInterval(saveTimer);
            saveTimer = setInterval(saveNow, Math.max(1, o.saveEverySec) * 1000);
            global.addEventListener('pagehide', saveNow);
            document.addEventListener('visibilitychange', () => {
                if (!document.hidden) return;
                saveNow();
                if (auto()) upload(false);   // 閉じる・隠れる時も、変わっていれば上げる
            });
            schedule();
            checkOnOpen();
        }

        return { start, mountUI, saveNow, restoreNow, uploadNow: () => upload(true), loadFromGist, status, keys: { session: SESSION, file: FILE, token: o.tokenKey, id: o.idKey } };
    }

    global.StateSync = { create, version: '1.1.1' };   // 1.1.0：版の日付（build）と、入れかえる時に足りない項目は手元の値を残す守り。1.1.1：うまくいかなかった時の知らせに GitHub の理由（番号・文・残り回数・待つ時間）を付ける
})(typeof window !== 'undefined' ? window : this);
