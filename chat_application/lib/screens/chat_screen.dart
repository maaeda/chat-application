import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:chat_application/main.dart';
import 'package:chat_application/post.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String name;

  const ChatScreen({super.key, required this.name});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatTimestamp(Timestamp ts) {
    final dt = ts.toDate();
    // intl を使ってローカライズされた日時フォーマットにする
    // 例: 2026/05/20 14:30
    return DateFormat('yyyy/MM/dd HH:mm').format(dt);
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログインが必要です')),
        );
      }
      return;
    }

    final newDoc = postsReference.doc();
    final newPost = Post(
      text: trimmed,
      createdAt: Timestamp.now(),
      posterName: user.displayName ?? '名無し',
      posterImageUrl: user.photoURL ?? '',
      posterId: user.uid,
      reference: newDoc,
    );

    try {
      await newDoc.set(newPost);
      if (mounted) _controller.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信に失敗しました: $e')),
        );
      }
    }
  }

  void _confirmDelete(String docId) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メッセージを削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await postsReference.doc(docId).delete();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('削除に失敗しました: $e')),
                  );
                }
              }
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Post>>(
              stream: postsReference.orderBy('createdAt').snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final post = doc.data();
                    final isMe = currentUid != null && post.posterId == currentUid;

                    final avatar = post.posterImageUrl.isNotEmpty
                        ? CircleAvatar(backgroundImage: NetworkImage(post.posterImageUrl))
                        : CircleAvatar(child: Text((post.posterName.isNotEmpty ? post.posterName[0] : '?')));

                    final messageBubble = Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: isMe ? Theme.of(context).colorScheme.primary : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            Text(post.posterName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(post.text, style: TextStyle(color: isMe ? Theme.of(context).colorScheme.onPrimary : Colors.black)),
                          const SizedBox(height: 6),
                          Text(_formatTimestamp(post.createdAt), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe) avatar,
                          if (!isMe) const SizedBox(width: 8),
                          GestureDetector(
                            onLongPress: () {
                              if (isMe) _confirmDelete(post.reference.id);
                            },
                            child: messageBubble,
                          ),
                          if (isMe) const SizedBox(width: 8),
                          if (isMe) avatar,
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 入力欄
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'メッセージを入力',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (text) => _sendMessage(text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _sendMessage(_controller.text),
                    child: const Text('送信'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

