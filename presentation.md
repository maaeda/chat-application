---
marp: true
theme: gaia
_class: lead
paginate: true
backgroundColor: #121214
color: #e4e4e7
style: |
  section {
    font-family: 'Inter', 'Noto Sans JP', sans-serif;
    padding: 40px;
    font-size: 24px;
  }
  h1 {
    color: #3b82f6;
  }
  h2 {
    color: #60a5fa;
    border-bottom: 2px solid #3f3f46;
  }
  footer {
    font-size: 0.5em;
    color: #71717a;
  }
  code {
    background-color: #27272a;
    color: #f4f4f5;
  }
  .highlight {
    color: #f59e0b;
    font-weight: bold;
  }
  .tech {
    color: #10b981;
    font-weight: bold;
  }
---

# Firebaseチャットアプリ × オンデバイスAI

### 〜 クラウドとローカルLLMを自在に行き来する、次世代Flutterチャット 〜

発表者: [名前/チーム名]

---

## 📱 アプリの概要

**Firebase** の強力なリアルタイム機能と、**オンデバイスAI** を融合させた、Flutter製のマルチプラットフォーム・チャットアプリケーション。

* **リアルタイム同期**: Firebase Auth & Cloud Firestoreによる低遅延な会話
* **ハイブリッドAIバックエンド**: APIとローカルLLMを動的に切り替え可能
* **実用的なAI機能**: スマートリプライ、テキストトーン変換、1対1デモチャット

---

## 🚨 背景：クラウドAI（API）が抱える課題

クラウド上のLLM（Gemini API等）は強力ですが、以下の懸念があります。

1. <span class="highlight">**コストの累積**</span>: 利用量に応じたAPI利用料が発生する
2. <span class="highlight">**プライバシー・セキュリティ**</span>: 会話データが外部サーバーに送信される
3. <span class="highlight">**ネットワーク依存**</span>: オフラインや電波の悪い場所では利用できない

---

## 💡 解決策：オンデバイスLLM（ローカルLLM）の統合

### **「完全オフライン・ゼロコスト・100%プライベート」**

* 端末のローカルリソースのみを使用するため、**通信が発生しない**
* 個人情報や機密性の高いメッセージを**端末外に送信しない**
* APIキー不要で、誰でも**完全無料**でAIの恩恵を享受できる

---

## 🌟 推し機能①：完全ローカルで動くLLM

`flutter_gemma` を利用し、モバイル端末上で直接LLMの推論を実行。

* **多彩なモデルをサポート**: 用途や端末スペックに応じて動的切り替え
  * **Gemma 3 270M / 1B** (Google): 高性能かつ軽量、最新の日本語対応
  * **SmolLM2 135M** (Hugging Face): 超軽量・超高速、低スペック端末向け
  * **Qwen2.5 0.5B** (Alibaba): バランスの取れた高品質応答
  * **Phi-4 mini 3.8B** (Microsoft): 最高品質の推論・思考力

---

## 🌟 推し機能②：シームレスなモデル管理とUX

ローカルで動かすからこその「使いやすさ」と「堅牢性」を追求。

* **オンデバイス・インストーラー**: 
  HuggingFaceからモデルをダウンロード。進捗バーで進捗を視覚化。
* <span class="highlight">**自己修復機能 (Self-Healing)**</span>:
  物理ファイルとDBメタデータの不一致を自動検知して修復。エラーによるクラッシュを防ぎます。
* **起動時自動ロード**:
  アプリ起動時にバックエンドがローカルLLMの場合、自動でメモリにロードして待機時間を削減。

---

## ⚡ 高度なAI統合アシスタント機能

ローカルまたはクラウドのLLMを活用し、チャット体験を向上。

* **スマートリプライ (返信サジェスト)**:
  直近の会話履歴（最大10件）を解析し、文脈に沿った3つの返信候補を提示。タップするだけで入力完了。
* **AIテキスト変換**:
  「カジュアル 🎉」「ビジネス 💼」「執事風 🎩」など、入力したテキストのトーンをAIが瞬時に変更。差分プレビューで確認してから適用可能。
* **AIアシスタントデモチャット**:
  AIと1対1で対話できる専用ルーム。

---

## 🛠️ 技術スタック

* **Frontend**: <span class="tech">Flutter</span> (SDK ^3.9.2, Dart ^3.5.0)
* **Database & Auth**: <span class="tech">Firebase</span> (Firestore, Firebase Auth)
* **On-Device LLM**: <span class="tech">flutter_gemma</span> (Google MediaPipe / Llama.cppベース)
* **Security**: <span class="tech">Firebase App Check</span> (Android: Play Integrity)
* **Models Hosting**: <span class="tech">Hugging Face</span>

---

## 🏁 まとめと今後の展望

### **「AIはクラウドから、あなたのポケットの中へ」**

* クラウドAIの「高度な推論」とローカルAIの「安全性・低コスト」を両立するハイブリッド構成の実現。
* 今後は、ローカルLLMを用いたユーザー好みのローカルファインチューニング（LoRA）や、マルチモーダル（画像・音声）のローカル処理への拡張を目指します。
