import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/services/model_repository.dart' as repo;
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:chat_application/services/ai_backend_service.dart';
import 'package:chat_application/widgets/profile_avatar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  User? _user;
  bool _isLoading = false;

  // AIバックエンド設定
  AiBackend _selectedBackend = AiBackend.googleAi;
  String _selectedModelName = kLocalModels.first.name;

  // モデルごとのインストール状態を保持するマップ
  Map<String, bool> _installedModels = {};
  // ダウンロード中のモデル名
  String? _downloadingModelName;
  double _downloadProgress = 0.0;

  // HuggingFace トークン設定用
  final TextEditingController _hfTokenController = TextEditingController();
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _initializeGoogleSignIn();
    _loadAiSettings();
    _auth.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _user = user;
        });
      }
    });
  }

  @override
  void dispose() {
    _hfTokenController.dispose();
    super.dispose();
  }

  String _getModelFileId(LocalModelInfo model) => model.url.split('/').last;

  Future<void> _loadAiSettings() async {
    final backend = await AiBackendService.getBackend();
    final modelName = await AiBackendService.getSelectedModelName();
    final hfToken = await AiBackendService.getHuggingFaceToken();

    // 全モデルのインストール状態を一括チェック（自己修復ロジック付き）
    final Map<String, bool> installed = {};
    final registry = ServiceRegistry.instance;
    final fs = registry.fileSystemService;

    for (final m in kLocalModels) {
      final fileId = _getModelFileId(m);
      final targetPath = await fs.getReadTargetPath(fileId);
      final file = File(targetPath);
      final fileExists = await file.exists();
      var isInstalled = await FlutterGemma.isModelInstalled(fileId);

      if (fileExists && !isInstalled) {
        try {
          debugPrint('LocalLLM Settings: モデルファイルは存在しますが、メタデータが未登録です。自動登録を実行します。');
          final sizeBytes = await file.length();
          final modelInfo = repo.ModelInfo(
            id: fileId,
            source: ModelSource.network(m.url),
            installedAt: DateTime.now(),
            sizeBytes: sizeBytes,
            type: repo.ModelType.inference,
            hasLoraWeights: false,
          );
          await registry.modelRepository.saveModel(modelInfo);
          isInstalled = true;
        } catch (e) {
          debugPrint('LocalLLM Settings: メタデータの自動登録に失敗しました: $e');
        }
      } else if (!fileExists && isInstalled) {
        try {
          await registry.modelRepository.deleteModel(fileId);
          isInstalled = false;
        } catch (e) {
          debugPrint('LocalLLM Settings: メタデータ削除に失敗しました: $e');
        }
      }

      installed[m.name] = isInstalled;
    }

    if (mounted) {
      setState(() {
        _selectedBackend = backend;
        _selectedModelName = modelName;
        _installedModels = installed;
        _hfTokenController.text = hfToken;
      });
    }
  }

  Future<void> _downloadModel(LocalModelInfo model) async {
    // HFトークンが必要なモデルで未入力の場合は警告ダイアログを表示
    if (model.needsAuth && _hfTokenController.text.trim().isEmpty) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.lock, size: 36, color: Colors.orange),
          title: const Text('HuggingFace トークンが必要です'),
          content: Text(
            '「${model.displayName}」はライセンス同意が必要なモデルです。\n\n'
            '① huggingface.co でモデルページを開き、利用規約に同意してください。\n'
            '② HuggingFace の設定からRead権限のアクセストークンを発行してください。\n'
            '③ 上部の「HuggingFace トークン」欄に入力してから再度ダウンロードしてください。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _downloadingModelName = model.name;
      _downloadProgress = 0.0;
    });

    try {
      final token = _hfTokenController.text.trim();
      await AiBackendService.setHuggingFaceToken(token);
      FlutterGemma.reset();
      await FlutterGemma.initialize(
        huggingFaceToken: token.isNotEmpty ? token : null,
      );

      await FlutterGemma.installModel(
        modelType: model.modelType,
      ).fromNetwork(model.url).withProgress((p) {
        if (mounted) setState(() => _downloadProgress = p / 100.0);
      }).install();

      // インストール状態を更新
      final isInstalled = await FlutterGemma.isModelInstalled(
        _getModelFileId(model),
      );
      if (mounted) {
        setState(() {
          _installedModels[model.name] = isInstalled;
          _downloadProgress = 1.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('${model.displayName} のダウンロードが完了しました！'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ダウンロードに失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingModelName = null;
        });
      }
    }
  }

  Future<void> _deleteModel(LocalModelInfo model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('モデルを削除しますか？'),
        content: Text('「${model.displayName}」を削除します。\n再度使用するにはダウンロードが必要になります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FlutterGemma.uninstallModel(_getModelFileId(model));
      setState(() {
        _installedModels[model.name] = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.displayName} を削除しました。')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  Future<void> _initializeGoogleSignIn() async {
    try {
      await _googleSignIn.initialize();
    } catch (e) {
      // 初期化済みの場合は無視
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        GoogleAuthProvider authProvider = GoogleAuthProvider();
        await _auth.signInWithPopup(authProvider);
      } else {
        final GoogleSignInAccount googleUser = await _googleSignIn
            .authenticate();
        final GoogleSignInAuthentication googleAuth = googleUser.authentication;
        final authorization = await googleUser.authorizationClient
            .authorizeScopes(['email']);
        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: authorization.accessToken,
          idToken: googleAuth.idToken,
        );
        await _auth.signInWithCredential(credential);
      }
      final user = _auth.currentUser;
      if (user != null && mounted) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName,
          'photoURL': user.photoURL,
          'updatedAt': Timestamp.now(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ログインに失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      if (!kIsWeb) await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('サインアウトに失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ===============================================================
  // UI ビルダー
  // ===============================================================

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildBackendSelector() {
    final backends = [
      (
        value: AiBackend.googleAi,
        title: 'Google AI Studio',
        subtitle: 'APIキー (GEMINI_API_KEY) を使用',
        icon: Icons.api,
        enabled: true,
      ),
      (
        value: AiBackend.firebaseAi,
        title: 'Firebase AI Logic',
        subtitle: 'Firebase プロジェクトの認証情報を使用',
        icon: Icons.local_fire_department,
        enabled: true,
      ),
      (
        value: AiBackend.localLlm,
        title: 'ローカルLLM (オンデバイス)',
        subtitle: kIsWeb ? 'Android / iOS のみ対応' : 'API不要・完全プライベート',
        icon: Icons.smartphone,
        enabled: !kIsWeb,
      ),
    ];

    return Column(
      children: backends.map((b) {
        final isSelected = _selectedBackend == b.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: InkWell(
            onTap: b.enabled
                ? () async {
                    await AiBackendService.setBackend(b.value);
                    setState(() => _selectedBackend = b.value);
                  }
                : null,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).dividerColor,
                  width: isSelected ? 2 : 1,
                ),
                color: isSelected
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.06)
                    : Theme.of(context).cardColor,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      b.icon,
                      size: 22,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : b.enabled
                          ? Theme.of(context).iconTheme.color
                          : Colors.grey,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: b.enabled ? null : Colors.grey,
                            ),
                          ),
                          Text(
                            b.subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: b.enabled
                                  ? Colors.grey
                                  : Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHfTokenSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.vpn_key_rounded,
                    color: Theme.of(context).colorScheme.secondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'HuggingFace アクセストークン',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: const Text(
                      '一部モデルで必要',
                      style: TextStyle(fontSize: 10, color: Colors.orange),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _hfTokenController,
                obscureText: _obscureToken,
                onChanged: (val) async {
                  await AiBackendService.setHuggingFaceToken(val.trim());
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'hf_xxxxxxxxxxxxxxxxxxxx',
                  prefixIcon: const Icon(Icons.key, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureToken ? Icons.visibility : Icons.visibility_off,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelCard(LocalModelInfo model) {
    final isSelected = _selectedModelName == model.name;
    final isInstalled = _installedModels[model.name] ?? false;
    final isDownloading = _downloadingModelName == model.name;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        onTap: () async {
          await AiBackendService.setSelectedModelName(model.name);
          setState(() => _selectedModelName = model.name);
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : Theme.of(context).dividerColor,
              width: isSelected ? 2 : 1,
            ),
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.05)
                : Theme.of(context).cardColor,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── ヘッダー行 ──
                Row(
                  children: [
                    // サイズバッジ
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        model.sizeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        model.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    // 認証必要バッジ
                    if (model.needsAuth)
                      Tooltip(
                        message: 'HFトークンとライセンス同意が必要',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock, size: 10, color: Colors.orange),
                              SizedBox(width: 3),
                              Text(
                                '要認証',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    // インストール済みアイコン
                    if (isInstalled && !isDownloading)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 18,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  model.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                // ── ダウンロード中 ──
                if (isDownloading) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _downloadProgress,
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ]
                // ── インストール済み：削除ボタン ──
                else if (isInstalled) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('削除', style: TextStyle(fontSize: 13)),
                        onPressed: () => _deleteModel(model),
                      ),
                    ],
                  ),
                ]
                // ── 未インストール：ダウンロードボタン ──
                else if (isSelected) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        'ダウンロード (${model.sizeLabel})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _downloadingModelName != null
                          ? null
                          : () => _downloadModel(model),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAiBackendSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        _buildSectionHeader('AI バックエンド'),
        _buildBackendSelector(),
        if (_selectedBackend == AiBackend.localLlm && !kIsWeb) ...[
          _buildSectionHeader('HuggingFace 認証'),
          _buildHfTokenSection(),
          _buildSectionHeader('モデルを選択'),
          ...kLocalModels.map(_buildModelCard),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildSectionHeader('アカウント'),
                if (_user == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Googleでサインイン'),
                      onPressed: _signInWithGoogle,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            ProfileAvatar(
                              imageUrl: _user!.photoURL,
                              name: _user!.displayName,
                              radius: 36,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _user!.displayName ?? 'ユーザー',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _user!.email ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.logout, size: 16),
                              label: const Text('サインアウト'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                              onPressed: _signOut,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                _buildAiBackendSection(),
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}
