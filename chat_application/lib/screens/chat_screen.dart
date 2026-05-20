import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:chat_application/main.dart';
import 'package:chat_application/post.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String name;

  const ChatScreen({super.key, required this.chatId, required this.name});

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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(dt.year, dt.month, dt.day);

    final time = DateFormat('HH:mm').format(dt);

    if (messageDate == today) {
      return time; // 今日: HH:mm
    } else if (messageDate == yesterday) {
      return '昨日 $time'; // 昨日: 昨日 HH:mm
    } else {
      return DateFormat('yyyy/MM/dd HH:mm').format(dt); // それ以外: yyyy/MM/dd HH:mm
    }
  }

  Future<void> _updateChatMetadata(String message) async {
    try {
      await chatsReference.doc(widget.chatId).update({
        'lastMessage': message,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      // Silently fail; chat metadata update is not critical
    }
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

    final newDoc = postsReferenceFor(widget.chatId).doc();
    final newPost = Post(
      text: trimmed,
      createdAt: Timestamp.now(),
      posterName: user.displayName ?? '名前を取得できません',
      posterImageUrl: user.photoURL ?? '',
      posterId: user.uid,
      reference: newDoc,
    );

    try {
      await newDoc.set(newPost);
      if (mounted) _controller.clear();
      // Update chat metadata (lastMessage, updatedAt)
      await _updateChatMetadata(trimmed);
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
                await postsReferenceFor(widget.chatId).doc(docId).delete();
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

  Future<void> _showAddMembersDialog() async {
    final List<String> _selectedNewMembers = [];
    final Map<String, String> _selectedNewMembersInfo = {}; // UID → 名前のマッピング
    final TextEditingController _searchController = TextEditingController();
    List<Map<String, String>> _searchResults = [];

    Future<void> _searchUsers(String query) async {
      if (query.isEmpty) {
        _searchResults.clear();
      } else {
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isGreaterThanOrEqualTo: query)
              .where('email', isLessThan: query + '\uffff')
              .limit(10)
              .get();

          _searchResults = snapshot.docs
              .map((doc) => {
                'uid': doc.id,
                'email': (doc['email'] ?? '') as String,
                'name': (doc['displayName'] ?? 'Unknown') as String,
              })
              .toList();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('検索に失敗しました: $e')),
            );
          }
        }
      }
    }

    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('メンバーを追加'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ユーザー検索欄
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
                  const SizedBox(height: 12),
                  // 検索結果リスト
                  if (_searchResults.isEmpty && _searchController.text.isNotEmpty)
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
                          final isSelected = _selectedNewMembers.contains(uid);
                          return CheckboxListTile(
                            title: Text(user['name'] ?? ''),
                            subtitle: Text(user['email'] ?? ''),
                            value: isSelected,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  if (!_selectedNewMembers.contains(uid)) {
                                    _selectedNewMembers.add(uid);
                                    // ユーザー情報も保存（タグ表示時に使用）
                                    _selectedNewMembersInfo[uid] = user['name'] ?? 'Unknown';
                                  }
                                } else {
                                  _selectedNewMembers.remove(uid);
                                  _selectedNewMembersInfo.remove(uid);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  // 選択したメンバーリスト（タグ表示）
                  if (_selectedNewMembers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Wrap(
                        spacing: 8,
                        children: _selectedNewMembers
                            .map((uid) {
                              // 保存されたユーザー情報から名前を取得（検索結果が空でも大丈夫）
                              final name = _selectedNewMembersInfo[uid] ?? uid;
                              return Chip(
                                label: Text(name),
                                deleteIcon: const Icon(Icons.close),
                                onDeleted: () => setState(() {
                                  _selectedNewMembers.remove(uid);
                                  _selectedNewMembersInfo.remove(uid);
                                }),
                              );
                            })
                            .toList(),
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
                  if (_selectedNewMembers.isEmpty) {
                    Navigator.of(context).pop();
                    return;
                  }

                  try {
                    // 現在の participants を取得
                    final chatDoc = await chatsReference.doc(widget.chatId).get();
                    final chat = chatDoc.data();
                    if (chat == null) {
                      Navigator.of(context).pop();
                      return;
                    }

                    // 新しい participants（重複を避ける）
                    final updatedParticipants = {...chat.participants, ..._selectedNewMembers}.toList();

                    // participants を更新
                    await chatsReference.doc(widget.chatId).update({
                      'participants': updatedParticipants,
                    });

                    Navigator.of(context).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('メンバーを追加しました')),
                      );
                    }
                  } catch (e) {
                    Navigator.of(context).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('メンバー追加に失敗しました: $e')),
                      );
                    }
                  }
                },
                child: const Text('追加'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _showMembersDialog() async {
    try {
      final chatDoc = await chatsReference.doc(widget.chatId).get();
      final chat = chatDoc.data();
      if (chat == null) return;

      final participantUids = chat.participants;

      // 各参加者のユーザー情報を取得
      final members = <Map<String, String>>[];
      for (final uid in participantUids) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          final userData = userDoc.data() ?? {};
          members.add({
            'uid': uid,
            'name': userData['displayName'] ?? 'Unknown',
            'email': userData['email'] ?? '',
            'photoURL': userData['photoURL'] ?? '', // 追加：プロフィール画像
          });
        } catch (e) {
          // ユーザー情報取得失敗時はスキップ
        }
      }

      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('チャットメンバー'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: members.length,
                itemBuilder: (context, index) {
                  final member = members[index];
                  final isMe = member['uid'] == FirebaseAuth.instance.currentUser?.uid;

                  // メンバーのアイコン（photoURL またはイニシャル）
                  final avatar = member['photoURL']!.isNotEmpty
                      ? CircleAvatar(backgroundImage: NetworkImage(member['photoURL']!))
                      : CircleAvatar(child: Text(member['name']?.substring(0, 1) ?? '?'));

                  return ListTile(
                    title: Text('${member['name']}${isMe ? ' (あなた)' : ''}'),
                    subtitle: Text(member['email'] ?? ''),
                    leading: avatar,
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('メンバー情報取得失敗: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _showAddMembersDialog,
            tooltip: 'メンバーを追加',
          ),
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: _showMembersDialog,
            tooltip: 'メンバー一覧',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Post>>(
              stream: postsReferenceFor(widget.chatId).orderBy('createdAt').snapshots(),
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

                    // 名前はバブルの外に表示し、バブルは本文と日時だけを囲む
                    final bubble = Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: isMe ? Theme.of(context).colorScheme.primary : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(post.text, style: TextStyle(color: isMe ? Theme.of(context).colorScheme.onPrimary : Colors.black)),
                          const SizedBox(height: 6),
                          Text(_formatTimestamp(post.createdAt), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    );

                    // 名前（投稿者）が必要な場合はバブルの外、上に表示する
                    final nameWidget = !isMe
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 4.0, left: 0),
                            child: Text(post.posterName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          )
                        : const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe) avatar,
                          if (!isMe) const SizedBox(width: 8),
                          // 名前＋バブルを縦に並べる
                          Flexible(
                            child: Column(
                              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                nameWidget,
                                GestureDetector(
                                  onLongPress: () {
                                    if (isMe) _confirmDelete(post.reference.id);
                                  },
                                  child: bubble,
                                ),
                              ],
                            ),
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

