# 次元おりがみ（ネイティブ版）を Firebase につなぐ準備

画面の並び（パネル・タブ・境目・表示モードなど）とショートカットを、Firebase に保存して、Mac と iPad でそろえるための準備です。

## 置き場所（決まりは変えなくてよい）

- プロジェクト：**nonis-apps**（Firestore は asia-northeast1）
- データ：
  - `apps/origami/users/{自分の番号}/settings/layout`（画面の並び）
  - `apps/origami/users/{自分の番号}/settings/shortcuts`（ショートカット）
- 守りの決まり（firestore.rules）は、プロジェクト共通の「`apps/{アプリ}/users/{本人}/**` は本人だけ」のままで使えます。

## ログイン

ほかのアプリ（ラベルメーカーなど）と同じ **Google** でログインします。自分の番号がウェブのアプリと同じになるので、あとでデータを分け合えます。
Firebase の大きな部品（SDK）は入れず、インターネットで直接やりとりします（ビルドを速いままにするため）。

## お願いしたいこと（Google Cloud の画面で。2〜3 分）

1. https://console.cloud.google.com/apis/credentials を開き、上のプロジェクトを **nonis-apps** にする
2. 「認証情報を作成」→「OAuth クライアント ID」
3. 「アプリケーションの種類」は **iOS**
   - 名前：`次元おりがみ Mac`
   - バンドル ID：`io.github.nonisgh.origami`
   - 「作成」
4. もう一度 2〜3 をくり返して、iPad 用も作る
   - 名前：`次元おりがみ iPad`
   - バンドル ID：`io.github.nonisgh.origami.ios`
5. できた 2 つの **クライアント ID**（`〜.apps.googleusercontent.com` で終わる長い文字）を、たぬおに教えてください
   - iOS の種類のクライアントには「秘密の鍵（クライアント シークレット）」はありません。クライアント ID は人に見せても大丈夫なものです

Firebase の画面（Authentication → Sign-in method）で **Google** がオンになっていることも確かめてください（ほかのアプリで使っているので、たぶんもうオンです）。

## そのあと、たぬおがすること

- アプリに「Google でログイン」を足す（ブラウザの小さな窓でログイン → アプリに戻る）
- 画面の並びとショートカットを、変えたら 1 秒くらいで保存・開いた時に読み込む
- 今アプリの中に保存しているショートカットは、最初にログインした時に Firebase へ移す
