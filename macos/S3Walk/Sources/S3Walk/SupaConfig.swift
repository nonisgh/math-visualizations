// Supabase のつなぎ先（ウェブ版の 共通部品/supa-sync/supa-config.js と同じプロジェクト）。どちらも公開してよい値（publishable key は公開用の鍵。読み書きの守りは表の RLS がする）。
//   秘密の鍵（sb_secret_… / service_role）は絶対にここへ書かない
enum SupaConfig {
    static let url = "https://jkpiaqrxuygqtonfikkc.supabase.co"
    static let anonKey = "sb_publishable_IjpsktD0soa2FptBa91wPw_aYRdvMT4"
    /// 表 mathviz_state の行の名前（Mac 版と iPad・iPhone 版で共通。ウェブ版の s3walk とは設定の形がちがうので別の行）
    static let app = "s3walk-native"
}
