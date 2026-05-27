# チャットアプリ（Firestore版） — 実装解説（初心者向け）

以下はプロジェクトの構造、主要ファイルの説明、Firestore のデータ設計、主要な処理フロー、よくあるトラブルと対処法などをまとめたドキュメントです。

## 目次
- 概要
- 主要ファイルと役割
- Firestore のデータ構造
- 画面ごとの処理フロー
  - チャット一覧（`ChatListScreen`）
  - チャット画面（`ChatScreen`）
  - 設定（`SettingsScreen`）とユーザー保存
- 重要なコードスニペット
- セキュリティ（Firestore ルール）例
- よくある問題と対処法
- ローカルでの実行手順
- 次の改善案

---

## 概要
- Flutter アプリで Firestore を使って複数チャット（グループ/個別）を持てる設計です。
- `chats` コレクションにチャット（グループ）を作り、そのサブコレクション `chats/{chatId}/posts` にメッセージを保存します。
- ユーザー情報は `users` コレクションに保存（Google ログイン時に自動保存）。

主な機能：
- 新チャット作成（参加者をメール検索から選択）
- チャット一覧（自分が参加しているチャットのみ表示）
- チャット内メッセージ送信（送信でチャットの `lastMessage` と `updatedAt` を更新）
- 自分のメッセージのみ削除可能
- チャットのメンバー一覧表示
- 日時表示は `intl` で「今日・昨日・それ以外」を区別

---

## 主要ファイルと役割
- `lib/main.dart` — Firebase 初期化、`chatsReference`（chats コレクションの converter）、`postsReferenceFor(chatId)` ヘルパを定義
- `lib/models/chat_model.dart` — `ChatModel`（チャットドキュメントのモデル）
- `lib/post.dart` — `Post`（メッセージモデル）
- `lib/screens/chat_list_screen.dart` — チャット一覧、チャット作成ダイアログ（検索・参加者選択）
- `lib/screens/chat_screen.dart` — 個別チャット画面（メッセージ表示・送信・削除、メンバー表示）
- `lib/screens/settings_screen.dart` — Google サインイン、サインイン時に `users` 保存

---

## Firestore のデータ構造（例）

- `users/{uid}`
```json
{
  "uid": "uid_123",
  "email": "user@example.com",
  "displayName": "山田 太郎",
  "photoURL": "https://..",
  "updatedAt": "<Timestamp>"
}
```

- `chats/{chatId}`
```json
{
  "name": "友達グループ",
  "avatarUrl": "",
  "lastMessage": "こんにちは",
  "updatedAt": "<Timestamp>",
  "participants": ["uid_123", "uid_456"]
}
```

- `chats/{chatId}/posts/{postId}`
```json
{
  "text": "こんにちは！",
  "createdAt": "<Timestamp>",
  "posterName": "山田 太郎",
  "posterImageUrl": "https://..",
  "posterId": "uid_123"
}
```

---

## 画面ごとの処理フロー（詳細）

### 新チャット作成（`ChatListScreen`）
1. FAB（New Chat）を押すとダイアログ表示
2. チャット名入力
3. ユーザー検索欄でメールを入力 → `_searchUsers(query)` が `users` コレクションを検索し候補を表示
4. 検索結果からチェックで参加者を追加（検索結果からのみ選べるようにして、存在しないユーザーの追加を防止）
5. 作成ボタンで `chatsReference.doc()` を作成して保存。現在のユーザーを必ず `participants` に含める

### チャット一覧（`ChatListScreen`）
- `chats` を `orderBy('updatedAt', descending: true)` で取得し、クライアント側で `participants` に自分が含まれるチャットのみ表示（複合インデックス未設定でも動作するように）

### メッセージ送信（`ChatScreen`）
1. 入力後 `_sendMessage(text)` を呼ぶ
2. `postsReferenceFor(chatId).doc()` を作り `Post` を `set()` で保存
3. 保存成功後、`chats/{chatId}` の `lastMessage` と `updatedAt` を更新
4. `StreamBuilder` により UI は自動更新

### メッセージ削除
- 長押しで `isMe` を判定して削除ダイアログ→`delete()` を実行
- クライアント側だけでなく Firestore ルールでも制御する必要あり

### メンバー一覧表示
- AppBar の People アイコンを押すと `_showMembersDialog()` が呼ばれ、`participants` の UID から `users/{uid}` を取得して表示

---

## 重要なコードスニペット

- `main.dart`（コレクション参照 helper）
```dart
final chatsReference = FirebaseFirestore.instance.collection('chats').withConverter<ChatModel>(
  fromFirestore: (snapshot, _) => ChatModel.fromFirestore(snapshot),
  toFirestore: (value, _) => value.toMap(),
);

CollectionReference<Post> postsReferenceFor(String chatId) =>
  FirebaseFirestore.instance
    .collection('chats')
    .doc(chatId)
    .collection('posts')
    .withConverter<Post>(
      fromFirestore: (snapshot, _) => Post.fromFirestore(snapshot),
      toFirestore: (value, _) => value.toMap(),
    );
```

- メッセージ送信（`ChatScreen._sendMessage`）
```dart
final newDoc = postsReferenceFor(widget.chatId).doc();
final newPost = Post(...);
await newDoc.set(newPost);
await chatsReference.doc(widget.chatId).update({
  'lastMessage': trimmed,
  'updatedAt': Timestamp.now(),
});
```

- 日時フォーマット（`intl` 使用）
```dart
String _formatTimestamp(Timestamp ts) {
  final dt = ts.toDate();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final messageDate = DateTime(dt.year, dt.month, dt.day);
  final time = DateFormat('HH:mm').format(dt);

  if (messageDate == today) {
    return time; // 14:30
  } else if (messageDate == yesterday) {
    return '昨日 $time'; // 昨日 09:15
  } else {
    return DateFormat('yyyy/MM/dd HH:mm').format(dt);
  }
}
```

---

## Firestore セキュリティルール（例）
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth.uid == uid;
    }

    match /chats/{chatId} {
      allow read: if request.auth != null && request.auth.uid in resource.data.participants;
      allow create: if request.auth != null;
      allow update: if request.auth != null && request.auth.uid in resource.data.participants;

      match /posts/{postId} {
        allow read: if request.auth != null && request.auth.uid in get(/databases/$(database)/documents/chats/$(chatId)).data.participants;
        allow create: if request.auth != null && request.auth.uid in get(/databases/$(database)/documents/chats/$(chatId)).data.participants;
        allow delete: if request.auth != null && request.auth.uid == resource.data.posterId;
      }
    }
  }
}
```

---

## よくある問題と対処法（要約）
- チャットが表示されない：`where(... arrayContains ...)` と `orderBy` の組み合わせは複合インデックスが必要。インデックス作成かクライアント側フィルタで回避
- 依存関係の競合：`pubspec.yaml` のバージョンを調整
- ダイアログの `RenderBox` エラー：`SizedBox` や `shrinkWrap: true` を使い ListView のサイズを明示する

---

## ローカルでの実行手順
```powershell
flutter pub get
flutter run -d chrome
```

---

## 次の改善案（例）
- Firestore の複合インデックスを作成してサーバ側でフィルタする（パフォーマンス向上）
- 未読カウント（unread）や画像メッセージ対応
- メッセージ送信前に AI で変換する機能（OpenAI 等）

---

必要であればこのドキュメントを README に統合したり、スクリーンショットやコードサンプルを増やしてさらに分かりやすくできます。どの部分を補足したいか教えてください。

