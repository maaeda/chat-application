import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:chat_application/main.dart';
import 'package:chat_application/models/chat_model.dart';
import 'package:chat_application/post.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart' as firebase_ai;
import 'package:google_generative_ai/google_generative_ai.dart' as google_ai;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:chat_application/services/ai_backend_service.dart';
import 'package:chat_application/services/ai_text_transform_service.dart';
import 'package:chat_application/widgets/profile_avatar.dart';
import 'package:chat_application/widgets/ai_transform_bottom_sheet.dart';
import 'package:chat_application/widgets/ai_transform_preview_dialog.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String name;
  final String chatType;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.name,
    this.chatType = ChatModel.typeNormal,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<String> _suggestedReplies = [];
  bool _isFetchingSuggestions = false;
  bool _isAiReplying = false;
  bool _isTransforming = false;
  String? _lastProcessedMessageId;
  bool get _isAiDemoChat => widget.chatType == ChatModel.typeAiDemo;
  bool _initialLoadComplete = false; // 初回ロード完了フラグ

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_controller.text.isNotEmpty && _suggestedReplies.isNotEmpty) {
      setState(() {
        _suggestedReplies.clear();
      });
    }
  }

  Future<void> _fetchSmartReplies(List<Post> recentPosts) async {
    if (_isFetchingSuggestions) return;
    setState(() {
      _isFetchingSuggestions = true;
      _suggestedReplies.clear();
    });

    String? errorMessage;

    try {
      const apiKey = String.fromEnvironment('GEMINI_API_KEY');
      final backend = await AiBackendService.getBackend();

      final history = recentPosts.length > 10
          ? recentPosts.sublist(0, 10).reversed.toList()
          : recentPosts.reversed.toList();
      final historyText = history
          .map((p) => '${p.posterName}: ${p.text}')
          .join('\n');

      // 設定画面からのバックエンド設定を優先、次にAPIKeyの有無で判定
      final effectiveBackend = (backend == AiBackend.googleAi && apiKey.isEmpty)
          ? AiBackend.firebaseAi
          : backend;

      String prompt = '';
      if (effectiveBackend == AiBackend.localLlm) {
        prompt =
            '''
Task: Suggest 3 short and natural Japanese replies based on the chat history below.
DO NOT use JSON. DO NOT use quotes. Just output exactly 3 lines of Japanese text, one option per line.

Chat history:
$historyText

Suggested replies (in Japanese):
1. ''';
      } else {
        prompt =
            '''
あなたはチャットアプリの返信サジェスト生成アシスタントです。
直近の会話履歴から、ユーザーが次に返信しそうな自然なフレーズを3つ提案してください。
必ず以下のJSON配列形式のみを返してください。余計なテキストやMarkdownは一切含めないでください。
例: ["了解しました！", "もう少し詳しく教えてください", "後で確認します"]

会話履歴:
$historyText
''';
      }

      String? text;

      switch (effectiveBackend) {
        case AiBackend.googleAi:
          // --- Google AI Studio ---
          final model = google_ai.GenerativeModel(
            model: 'gemini-2.5-flash',
            apiKey: apiKey,
          );
          final response = await model.generateContent([
            google_ai.Content.text(prompt),
          ]);
          text = response.text;

        case AiBackend.firebaseAi:
          // --- Firebase AI Logic ---
          final model = firebase_ai.FirebaseAI.googleAI().generativeModel(
            model: 'gemini-2.5-flash',
          );
          final response = await model.generateContent([
            firebase_ai.Content.text(prompt),
          ]);
          text = response.text;

        case AiBackend.localLlm:
          // --- ローカルLLM (flutter_gemma) ---
          final isReady = await AiBackendService.ensureLocalModelReady();
          if (!isReady) {
            errorMessage = 'モデルが未インストールです。設定画面からダウンロードしてください。';
            return;
          }
          final inferenceModel = await FlutterGemma.getActiveModel(
            maxTokens: 1024,
          );
          final session = await inferenceModel.createSession();
          await session.addQueryChunk(Message(text: prompt, isUser: true));
          text = await session.getResponse();
          await session.close();
      }

      debugPrint('Smart reply raw response: $text');

      if (text == null || text.trim().isEmpty) {
        errorMessage = 'レスポンスが空です';
        return;
      }

      // Markdown形式 (```json ... ```) が含まれてしまった場合への堅牢な対策
      text = text.replaceAll(RegExp(r'```json', caseSensitive: false), '');
      text = text.replaceAll('```', '');
      text = text.trim();

      // JSONの先頭 '[' と末尾 ']' を抽出して安全にパース
      final startIdx = text.indexOf('[');
      final endIdx = text.lastIndexOf(']');

      List<String> suggestions = [];

      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        final jsonText = text.substring(startIdx, endIdx + 1);
        final List<dynamic> parsed = jsonDecode(jsonText);
        suggestions = parsed.map((e) => e.toString()).toList();
      } else {
        // フォールバック: 行ごとに分割してサジェストにする
        final lines = text
            .split('\n')
            .map(
              (e) => e.replaceAll(RegExp(r'^[-*0-9.\s]+'), ''),
            ) // 行頭の箇条書き記号を削除
            .map(
              (e) => e.replaceAll(RegExp(r'[{}"\[\]:]+'), ''),
            ) // JSON由来の記号を削除 (英字は消さない)
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty && e.length < 50)
            .take(3)
            .toList();
        if (lines.isNotEmpty) {
          suggestions = lines;
        } else {
          String preview = text.replaceAll(RegExp(r'[\r\n\t\\]+'), ' ');
          if (preview.length > 40) preview = preview.substring(0, 40) + '...';
          errorMessage = 'サジェストを生成できませんでした ($preview)';
          return;
        }
      }

      if (mounted && _controller.text.isEmpty) {
        setState(() {
          _suggestedReplies = suggestions;
        });
      }
    } catch (e) {
      errorMessage = 'エラー: $e';
      debugPrint('Smart reply error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingSuggestions = false;
        });
        if (errorMessage != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errorMessage!)));
        }
      }
    }
  }

  Future<String> _generateAiText(String prompt, {int maxTokens = 1024}) async {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    final backend = await AiBackendService.getBackend();
    final effectiveBackend = (backend == AiBackend.googleAi && apiKey.isEmpty)
        ? AiBackend.firebaseAi
        : backend;

    switch (effectiveBackend) {
      case AiBackend.googleAi:
        final model = google_ai.GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: apiKey,
        );
        final response = await model.generateContent([
          google_ai.Content.text(prompt),
        ]);
        return response.text?.trim() ?? '';

      case AiBackend.firebaseAi:
        final model = firebase_ai.FirebaseAI.googleAI().generativeModel(
          model: 'gemini-2.5-flash',
        );
        final response = await model.generateContent([
          firebase_ai.Content.text(prompt),
        ]);
        return response.text?.trim() ?? '';

      case AiBackend.localLlm:
        final isReady = await AiBackendService.ensureLocalModelReady();
        if (!isReady) {
          throw Exception('ローカルLLMモデルが未インストールです。設定画面からダウンロードしてください。');
        }
        final inferenceModel = await FlutterGemma.getActiveModel(
          maxTokens: maxTokens,
        );
        final session = await inferenceModel.createSession();
        await session.addQueryChunk(Message(text: prompt, isUser: true));
        final text = await session.getResponse();
        await session.close();
        return text.trim();
    }
  }

  Future<void> _sendAiDemoReply() async {
    if (_isAiReplying) return;

    setState(() {
      _isAiReplying = true;
      _suggestedReplies.clear();
    });

    try {
      final snapshot = await postsReferenceFor(widget.chatId)
          .orderBy('createdAt', descending: true)
          .limit(12)
          .get();

      final history = snapshot.docs.map((doc) => doc.data()).toList().reversed;
      final historyText = history
          .map((post) => '${post.posterName}: ${post.text}')
          .join('\n');

      final prompt =
          '''
あなたはチャットアプリのデモ用AIアシスタントです。
ユーザーと自然な日本語で会話してください。
返答は1〜3文で短く、親しみやすく、具体的にしてください。
Markdown、箇条書き、JSONは使わないでください。

会話履歴:
$historyText

AIアシスタントの次の返答:
''';

      var aiText = await _generateAiText(prompt, maxTokens: 512);
      aiText = aiText
          .replaceAll(RegExp(r'```.*?```', dotAll: true), '')
          .replaceAll(RegExp(r'^AIアシスタント[:：]\s*'), '')
          .trim();

      if (aiText.isEmpty) {
        aiText = 'すみません、うまく返答を作れませんでした。もう一度送ってください。';
      }

      final newDoc = postsReferenceFor(widget.chatId).doc();
      await newDoc.set(
        Post(
          text: aiText,
          createdAt: Timestamp.now(),
          posterName: 'AIアシスタント',
          posterImageUrl: '',
          posterId: 'ai_assistant',
          reference: newDoc,
        ),
      );
      await _updateChatMetadata(aiText);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AI返信の生成に失敗しました: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isAiReplying = false;
        });
      }
    }
  }

  /// AI変換ボトムシートを表示し、変換フローを開始する
  Future<void> _showTransformBottomSheet() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final style = await AiTransformBottomSheet.show(context);
    if (style == null || !mounted) return;

    await _performTransform(text, style);
  }

  /// AIでテキストを変換し、プレビューダイアログを表示する
  Future<void> _performTransform(String originalText, TransformStyle style) async {
    // 変換中のローディングダイアログを表示
    setState(() => _isTransforming = true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('AIで変換中...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final transformedText = await AiTextTransformService.transformText(
        originalText,
        style,
      );

      // ローディングダイアログを閉じる
      if (mounted) Navigator.of(context).pop();
      setState(() => _isTransforming = false);

      if (!mounted) return;

      // スタイル情報を取得
      final styleInfo = kTransformStyles.firstWhere(
        (s) => s.style == style,
      );

      // プレビューダイアログを表示
      final action = await AiTransformPreviewDialog.show(
        context,
        originalText: originalText,
        transformedText: transformedText,
        styleInfo: styleInfo,
      );

      if (!mounted) return;

      switch (action) {
        case TransformPreviewAction.apply:
          // 変換後テキストを入力欄にセット
          _controller.text = transformedText;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: transformedText.length),
          );
          break;
        case TransformPreviewAction.retry:
          // 再度ボトムシートを表示
          await _showTransformBottomSheet();
          break;
        case TransformPreviewAction.cancel:
        case null:
          // 何もしない（元のテキストのまま）
          break;
      }
    } catch (e) {
      // ローディングダイアログを閉じる
      if (mounted) Navigator.of(context).pop();
      setState(() => _isTransforming = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI変換に失敗しました: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
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
      return DateFormat(
        'yyyy/MM/dd HH:mm',
      ).format(dt); // それ以外: yyyy/MM/dd HH:mm
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ログインが必要です')));
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
      if (_isAiDemoChat) {
        await _sendAiDemoReply();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('送信に失敗しました: $e')));
      }
    }
  }

  void _confirmDelete(String docId) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メッセージを削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await postsReferenceFor(widget.chatId).doc(docId).delete();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
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
              .map(
                (doc) => {
                  'uid': doc.id,
                  'email': (doc['email'] ?? '') as String,
                  'name': (doc['displayName'] ?? 'Unknown') as String,
                },
              )
              .toList();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('検索に失敗しました: $e')));
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
                                    _selectedNewMembersInfo[uid] =
                                        user['name'] ?? 'Unknown';
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
                        children: _selectedNewMembers.map((uid) {
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
                  if (_selectedNewMembers.isEmpty) {
                    Navigator.of(context).pop();
                    return;
                  }

                  try {
                    // 現在の participants を取得
                    final chatDoc = await chatsReference
                        .doc(widget.chatId)
                        .get();
                    final chat = chatDoc.data();
                    if (chat == null) {
                      Navigator.of(context).pop();
                      return;
                    }

                    // 新しい participants（重複を避ける）
                    final updatedParticipants = {
                      ...chat.participants,
                      ..._selectedNewMembers,
                    }.toList();

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
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
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
                  final isMe =
                      member['uid'] == FirebaseAuth.instance.currentUser?.uid;

                  // メンバーのアイコン（photoURL またはイニシャル）
                  return ListTile(
                    title: Text('${member['name']}${isMe ? ' (あなた)' : ''}'),
                    subtitle: Text(member['email'] ?? ''),
                    leading: ProfileAvatar(
                      imageUrl: member['photoURL'],
                      name: member['name'],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('メンバー情報取得失敗: $e')));
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
              stream: postsReferenceFor(
                widget.chatId,
              ).orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];

                if (docs.isNotEmpty) {
                  final lastDoc = docs.first;
                  final lastId = lastDoc.id;
                  final lastPost = lastDoc.data();
                  final isFromOther = lastPost.posterId != currentUid;

                  if (lastId != _lastProcessedMessageId) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      if (_lastProcessedMessageId == lastId) return; // 二重実行防止

                      final isFirstLoad = !_initialLoadComplete;

                      setState(() {
                        _lastProcessedMessageId = lastId;
                        _initialLoadComplete = true;
                        if (!isFromOther) _suggestedReplies.clear();
                      });

                      // 初回ロードはAPIを叩かない。相手のメッセージ（通常チャットの他メンバーやAIアシスタント）が来た時だけ生成
                      if (!isFirstLoad && isFromOther) {
                        _fetchSmartReplies(docs.map((d) => d.data()).toList());
                      }
                    });
                  }
                }

                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    // サジェスト欄が表示中は下部に余白を追加
                    (_isAiReplying ||
                            _isFetchingSuggestions ||
                            _suggestedReplies.isNotEmpty)
                        ? 62
                        : 12,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final post = doc.data();
                    final isMe =
                        currentUid != null && post.posterId == currentUid;

                    final avatar = ProfileAvatar(
                      imageUrl: post.posterImageUrl,
                      name: post.posterName,
                    );

                    // 名前はバブルの外に表示し、バブルは本文と日時だけを囲む
                    final bubble = Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isMe
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.text,
                            style: TextStyle(
                              color: isMe
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Colors.black,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatTimestamp(post.createdAt),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    );

                    // 名前（投稿者）が必要な場合はバブルの外、上に表示する
                    final nameWidget = !isMe
                        ? Padding(
                            padding: const EdgeInsets.only(
                              bottom: 4.0,
                              left: 0,
                            ),
                            child: Text(
                              post.posterName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe) avatar,
                          if (!isMe) const SizedBox(width: 8),
                          // 名前＋バブルを縦に並べる
                          Flexible(
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isAiReplying ||
                    _isFetchingSuggestions ||
                    _suggestedReplies.isNotEmpty)
                  Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    alignment: Alignment.centerLeft,
                    child: _isAiReplying
                        ? const Row(
                            children: [
                              SizedBox(width: 8),
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('AIが入力中...'),
                            ],
                          )
                        : _isFetchingSuggestions
                        ? const Padding(
                            padding: EdgeInsets.only(left: 8.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _suggestedReplies.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final text = _suggestedReplies[index];
                              return ActionChip(
                                label: Text(text),
                                onPressed: () {
                                  _sendMessage(text);
                                  setState(() {
                                    _suggestedReplies.clear();
                                  });
                                },
                              );
                            },
                          ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 6.0,
                  ),
                  child: Row(
                    children: [
                      // AI変換ボタン
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, child) {
                          final hasText = value.text.trim().isNotEmpty;
                          return IconButton(
                            icon: const Text('✨', style: TextStyle(fontSize: 20)),
                            tooltip: 'AI変換',
                            onPressed: (hasText && !_isTransforming)
                                ? _showTransformBottomSheet
                                : null,
                            style: IconButton.styleFrom(
                              padding: const EdgeInsets.all(8),
                              minimumSize: const Size(40, 40),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          maxLines: null, // 複数行入力を許可
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            hintText: 'メッセージを入力',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 送信ボタンは下揃えにして複数行でも使いやすくする
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: ElevatedButton(
                          onPressed: () => _sendMessage(_controller.text),
                          child: const Text('送信'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
