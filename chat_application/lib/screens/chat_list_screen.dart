import 'package:flutter/material.dart';
import 'chat_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_model.dart';
import '../main.dart';
import '../widgets/profile_avatar.dart';
import 'package:intl/intl.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final List<String> _selectedParticipants = []; // 選択した参加者の UID リスト
  final TextEditingController _chatNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, String>> _searchResults = []; // {uid, email, name}

  @override
  void dispose() {
    _chatNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    try {
      // 簡易検索：email に基づく検索（実装時は Firestore インデックス設定が必要な場合あり）
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isGreaterThanOrEqualTo: query)
          .where('email', isLessThan: query + '\uffff')
          .limit(10)
          .get();

      final results = snapshot.docs
          .map(
            (doc) => {
              'uid': doc.id,
              'email': (doc['email'] ?? '') as String,
              'name': (doc['displayName'] ?? 'Unknown') as String,
            },
          )
          .toList();

      setState(() => _searchResults = results);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('検索に失敗しました: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('チャット一覧'),
        actions: [
          // tap 可能にするために InkWell を使います。
          InkWell(
            onTap: () {
              // プロフィール画面などへの遷移を追加予定
            },
            child: ProfileAvatar(
              imageUrl: FirebaseAuth.instance.currentUser?.photoURL,
              name: FirebaseAuth.instance.currentUser?.displayName,
              radius: 20,
            ),
          ),
        ],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<QuerySnapshot<ChatModel>>(
        stream: chatsReference
            .orderBy('updatedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          final currentUid = FirebaseAuth.instance.currentUser?.uid;

          // クライアント側で自分が参加しているチャットのみフィルタリング
          final userChats = docs
              .where((doc) => doc.data().participants.contains(currentUid))
              .toList();

          if (userChats.isEmpty) {
            return const Center(child: Text('チャットがありません。新しいチャットを作成してください。'));
          }

          return ListView.builder(
            itemCount: userChats.length,
            itemBuilder: (context, index) {
              final chat = userChats[index].data();
              final chatId = userChats[index].id;
              final time = DateFormat(
                'yyyy/MM/dd HH:mm',
              ).format(chat.updatedAt.toDate());

              return ListTile(
                leading: ProfileAvatar(
                  imageUrl: chat.avatarUrl,
                  name: chat.name,
                ),
                title: Text(
                  chat.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  chat.lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  time,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ChatScreen(chatId: chatId, name: chat.name),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          _selectedParticipants.clear();
          _chatNameController.clear();
          _searchController.clear();
          _searchResults.clear();

          await showDialog<void>(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: const Text('新しいチャットを作成'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // チャット名入力
                      TextField(
                        controller: _chatNameController,
                        decoration: const InputDecoration(labelText: 'チャット名'),
                      ),
                      const SizedBox(height: 16),
                      // 参加者検索
                      TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'ユーザーを検索（メール）',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (query) {
                          _searchUsers(query);
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      // 検索結果リスト（結果がない場合はメッセージを表示）
                      if (_searchResults.isEmpty &&
                          _searchController.text.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('検索結果がありません'),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 150),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final user = _searchResults[index];
                              final uid = user['uid'] ?? '';
                              final isSelected = _selectedParticipants.contains(
                                uid,
                              );
                              return CheckboxListTile(
                                title: Text(user['name'] ?? ''),
                                subtitle: Text(user['email'] ?? ''),
                                value: isSelected,
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      if (!_selectedParticipants.contains(
                                        uid,
                                      )) {
                                        _selectedParticipants.add(uid);
                                      }
                                    } else {
                                      _selectedParticipants.remove(uid);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 12),
                      // 選択した参加者リスト表示
                      if (_selectedParticipants.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Wrap(
                            spacing: 8,
                            children: _selectedParticipants.map((uid) {
                              final user = _searchResults.firstWhere(
                                (u) => u['uid'] == uid,
                                orElse: () => {'name': uid, 'uid': uid},
                              );
                              return Chip(
                                label: Text(user['name'] ?? uid),
                                deleteIcon: const Icon(Icons.close),
                                onDeleted: () => setState(
                                  () => _selectedParticipants.remove(uid),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('キャンセル'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final name = _chatNameController.text.trim();
                      final currentUid = FirebaseAuth.instance.currentUser?.uid;
                      if (currentUid == null) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('ログインが必要です')),
                        );
                        return;
                      }

                      // 参加者に現在のユーザーを追加
                      final participants = {
                        currentUid,
                        ..._selectedParticipants,
                      }.toList();

                      final newChatDoc = chatsReference.doc();
                      final chatModel = ChatModel(
                        name: name.isNotEmpty ? name : '新しいチャット',
                        avatarUrl: '',
                        lastMessage: '',
                        updatedAt: Timestamp.now(),
                        participants: participants,
                        reference: newChatDoc,
                      );

                      await newChatDoc.set(chatModel);
                      Navigator.of(context).pop();
                    },
                    child: const Text('作成'),
                  ),
                ],
              ),
            ),
          );
        },
        label: const Text('New Chat'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class Chat {
  final String name;
  final String message;
  final String time;
  final String avatarUrl;

  Chat({
    required this.name,
    required this.message,
    required this.time,
    required this.avatarUrl,
  });
}
