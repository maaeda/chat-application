# Chat Application

Firebase バックエンドと高度な AI 機能を統合した、Flutter 製のマルチプラットフォーム対応チャットアプリケーションです。
Google AI Studio、Firebase Vertex AI、およびオンデバイスでのローカル LLM（Gemma 等）の3つの AI バックエンド切り替えをサポートしており、スマートリプライや AI テキスト変換などの先進的な AI 機能を提供します。

---

## 🌟 主な機能

### 1. チャット基本機能
- **Google アカウント認証**: Google アカウントを使用した安全なサインインとサインアウト。
- **リアルタイムメッセージング**: Cloud Firestore を使用した低遅延なリアルタイム送受信。
- **通常チャットルームの作成**: メールアドレスによるユーザー検索を行い、1対1または複数人でのグループチャットを動的に作成可能。
- **チャット管理**: メッセージの削除、チャットルームへの後からのメンバー追加、およびメンバー一覧の表示。

### 2. AI 統合機能
- **マルチ AI バックエンド対応**: 設定画面から使用する AI エンジンを動的に切り替え可能。
  - **Google AI Studio**: `gemini-2.5-flash` を使用（環境変数 `GEMINI_API_KEY` が必要）。
  - **Firebase AI Logic**: Firebase Vertex AI 経由で `gemini-2.5-flash` を安全に使用。
  - **ローカル LLM (オンデバイス)**: `flutter_gemma` を利用し、端末ローカルで LLM を直接実行（モバイル端末のみ、完全オフライン・プライバシー重視）。
- **スマートリプライ (返信サジェスト)**:
  - 直近のチャット履歴（最大10件）を AI が自動解析し、文脈に適した 3 つの日本語返信候補を提案します。候補をタップするだけで素早くメッセージを入力できます。
- **AI テキスト変換**:
  - メッセージ入力中に、入力テキストを指定したスタイルに AI で変換できます。
  - **変換スタイル**: カジュアル 🎉, 丁寧 🙇, ビジネス 💼, やさしい 🌸, 要約 📝, AI風 🤖, 執事風 🎩, 先生風 👨‍🏫
  - 変換前後の差分を確認できるプレビューダイアログを搭載し、「適用」「別のスタイルでやり直す」「キャンセル」が選択可能です。
- **AI アシスタントデモチャット**:
  - AI アシスタントと 1対1 で会話ができる専用のチャットルームです。メッセージを送信すると、AI が文脈を理解して自動的にリアルタイム返信を行います。
- **オンデバイス LLM 管理**:
  - 設定画面からオンデバイスモデルのダウンロード（進捗バー表示）、削除、および HuggingFace アクセストークン（Read権限）の管理が可能。
  - 物理ファイルとメタデータの不一致を自動修復する機能や、起動時のモデル自動ロード機能を搭載しています。

---

## 🛠️ 技術スタックとパッケージ

- **フレームワーク**: [Flutter](https://flutter.dev/) (SDK: `^3.9.2`, Dart: `^3.5.0`)
- **データベース & バックエンド**: [Firebase Suite](https://firebase.google.com/)
  - `firebase_core`: Firebase の初期化
  - `firebase_auth` & `google_sign_in`: ユーザー認証と Google 連携
  - `cloud_firestore`: チャットルーム、メッセージ履歴、ユーザーデータのリアルタイム同期
  - `firebase_app_check`: アプリのセキュリティ保護（Android では Play Integrity を利用）
  - `firebase_ai` & `google_generative_ai`: クラウド側での Gemini API 呼び出し
- **オンデバイス AI**:
  - `flutter_gemma`: 端末上での LLM (Gemma 3 等) の推論実行およびモデル管理
- **その他主要ライブラリ**:
  - `shared_preferences`: AI バックエンド設定やトークンなどの永続化
  - `intl`: 日付・時間のフォーマット表示

---

## 🤖 ローカル LLM サポートモデル

オンデバイス LLM モードでは、以下の小型・軽量モデルのダウンロードに対応しています：

| モデル名 | ディスプレイ表示名 | サイズ | 特徴 | HF認証 |
| :--- | :--- | :---: | :--- | :---: |
| `gemma3-270m-it` | Gemma 3 270M | 270M | Googleの最軽量モデル。高速動作。 | **要** |
| `smollm2-135m-it` | SmolLM2 135M | 135M | 超軽量・超高速。動作確認や低スペック端末向け。 | 不要 |
| `qwen2.5-0.5b-it` | Qwen2.5 0.5B | 0.5B | 軽量ながら高品質な応答が可能。 | 不要 |
| `gemma3-1b-it` | Gemma 3 1B | 1B | Googleの最新軽量モデル。高精度な日本語対応。 | **要** |
| `phi-4-mini-it` | Phi-4 mini | 3.8B | Microsoftの高性能小型モデル。最高品質の推論。 | 不要 |

> [!NOTE]
> 「要」となっているモデルを利用するには、`huggingface.co` にて各モデルの利用規約に同意し、設定画面から HuggingFace の Read トークンを設定する必要があります。

---

## 📂 ディレクトリ構造

```text
lib/
├── main.dart                      # アプリのエントリーポイント、初期化、全体ルーティング
├── firebase_options.dart          # Firebase CLI で自動生成されるプラットフォーム設定
├── post.dart                      # メッセージのデータモデルクラス (Post)
├── models/
│   └── chat_model.dart            # チャットルームのデータモデルクラス (ChatModel)
├── screens/
│   ├── chat_list_screen.dart      # チャット一覧表示、新規チャット作成、AIデモチャットの起動
│   ├── chat_screen.dart          # メッセージ表示・送受信、スマートリプライ、テキスト変換、メンバー管理
│   └── settings_screen.dart       # アカウント管理、AI バックエンド切り替え、ローカルLLMダウンロード
├── services/
│   ├── ai_backend_service.dart    # バックエンド設定の管理、ローカルモデル一覧、起動時ロード・自己修復
│   └── ai_text_transform_service.dart # 各変換スタイルのプロンプト構築および AI 変換処理
└── widgets/
    ├── ai_transform_bottom_sheet.dart # テキスト変換スタイル選択用のボトムシート
    ├── ai_transform_preview_dialog.dart # 変換結果のプレビューとアクションダイアログ
    └── profile_avatar.dart        # ユーザーのアイコン/イニシャルを表示するアバターウィジェット
```

---

## 🚀 セットアップと実行手順

### 1. 前提条件
- Flutter SDK (`^3.9.2` 以上) がインストールされていること。
- Firebase プロジェクトが作成され、Flutter アプリと連携設定されていること。

### 2. 依存関係のインストール
プロジェクトのルートディレクトリで以下を実行します：
```bash
flutter pub get
```

### 3. Firebase の構成
FlutterFire CLI を使用して、Firebase のプラットフォーム別設定を構成します：
```bash
flutterfire configure
```
※ Firestore コレクションとして `chats` (およびそのサブコレクション `posts`), `users` を作成してください。また、更新順ソートのため `chats` コレクションの `updatedAt` フィールドに対するインデックス作成が必要になる場合があります。

### 4. 環境変数の設定 (Google AI Studio 用)
Google AI Studio の API キーを使用して Gemini API を実行する場合、ビルドまたは実行時に `GEMINI_API_KEY` を環境変数として渡す必要があります：
```bash
flutter run --dart-define=GEMINI_API_KEY=YOUR_GEMINI_API_KEY
```

### 5. アプリの起動
通常起動：
```bash
flutter run
```
※ Web版はローカルLLMに対応していないため、ローカルLLM機能を使用する場合は Android または iOS の実機/エミュレータで起動してください。
