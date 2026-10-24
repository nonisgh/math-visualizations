/*!
 * supa-config.js — supa-sync のつなぎ先（Supabase のプロジェクト）。数学アプリで共通。
 * どちらも公開してよい値（publishable key は公開用の鍵。読み書きの守りは表の RLS がする）。
 * 秘密の鍵（sb_secret_… / service_role）は絶対にここへ書かない。
 */
window.SUPA_SYNC_CONFIG = {
    url: 'https://jkpiaqrxuygqtonfikkc.supabase.co',
    anonKey: 'sb_publishable_IjpsktD0soa2FptBa91wPw_aYRdvMT4',
};
