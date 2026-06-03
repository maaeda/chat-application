import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:chat_application/services/ai_backend_service.dart';

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
  bool _isModelInstalled = false;
  bool _isDownloading = false;
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

  Future<void> _loadAiSettings() async {
    final backend = await AiBackendService.getBackend();
    final modelName = await AiBackendService.getSelectedModelName();
    final hfToken = await AiBackendService.getHuggingFaceToken();
    final installed = FlutterGemma.hasActiveModel();
    if (mounted) {
      setState(() {
        _selectedBackend = backend;
        _selectedModelName = modelName;
        _isModelInstalled = installed;
        _hfTokenController.text = hfToken;
      });
    }
  }

  Future<void> _downloadModel() async {
    final model = AiBackendService.getModelByName(_selectedModelName);
    setState(() {
      _isDownloading = true;
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
        modelType: ModelType.gemmaIt,
      ).fromNetwork(model.url)
          .withProgress((p) {
            if (mounted) setState(() => _downloadProgress = p / 100.0);
          })
          .install();
      final installed = FlutterGemma.hasActiveModel();
      if (mounted) {
        setState(() {
          _isModelInstalled = installed;
          _downloadProgress = 1.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('モデルのダウンロードが完了しました！')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ダウンロードに失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
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
    setState(() {
      _isLoading = true;
    });

    try {
      if (kIsWeb) {
        // Web用のGoogleログイン
        GoogleAuthProvider authProvider = GoogleAuthProvider();
        await _auth.signInWithPopup(authProvider);
      } else {
        // モバイル(Android/iOS)用のGoogleログイン
        // 1. Google認証
        final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

        // 2. 認証情報の取得 (idToken)
        final GoogleSignInAuthentication googleAuth = googleUser.authentication;

        // 3. アクセストークンの取得
        final authorization =
            await googleUser.authorizationClient.authorizeScopes(['email']);

        // 4. Firebase用クレデンシャルの作成
        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: authorization.accessToken,
          idToken: googleAuth.idToken,
        );

        // 5. Firebaseにサインイン
        await _auth.signInWithCredential(credential);
      }
      // ログイン後、ユーザープロフィールを Firestore に保存
      final user = _auth.currentUser;
      if (user != null && mounted) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {
            'uid': user.uid,
            'email': user.email,
            'displayName': user.displayName,
            'photoURL': user.photoURL,
            'updatedAt': Timestamp.now(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ログインに失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      // Web環境以外でのみGoogle Sign Outを実行
      if (!kIsWeb) {
        await _googleSignIn.signOut();
      }
      // Firebase Sign Out
      await _auth.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('サインアウトに失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildAiBackendSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'AIバックエンド設定',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
          ),
        ),
        RadioListTile<AiBackend>(
          title: const Text('Google AI Studio'),
          subtitle: const Text('APIキー (--dart-define=GEMINI_API_KEY) を使用'),
          value: AiBackend.googleAi,
          groupValue: _selectedBackend,
          onChanged: (v) async {
            if (v == null) return;
            await AiBackendService.setBackend(v);
            setState(() => _selectedBackend = v);
          },
        ),
        RadioListTile<AiBackend>(
          title: const Text('Firebase AI Logic'),
          subtitle: const Text('Firebase プロジェクトの認証情報を使用'),
          value: AiBackend.firebaseAi,
          groupValue: _selectedBackend,
          onChanged: (v) async {
            if (v == null) return;
            await AiBackendService.setBackend(v);
            setState(() => _selectedBackend = v);
          },
        ),
        RadioListTile<AiBackend>(
          title: const Text('ローカルLLM (オンデバイス)'),
          subtitle: const Text('API不要・プライバシー保護。遅い可能性あり。Android/iOSのみ'),
          value: AiBackend.localLlm,
          groupValue: _selectedBackend,
          onChanged: kIsWeb
              ? null
              : (v) async {
                  if (v == null) return;
                  await AiBackendService.setBackend(v);
                  setState(() => _selectedBackend = v);
                },
        ),
        if (_selectedBackend == AiBackend.localLlm && !kIsWeb) ..._buildLocalLlmSection(),
      ],
    );
  }

  List<Widget> _buildLocalLlmSection() {
    final model = AiBackendService.getModelByName(_selectedModelName);
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'HuggingFace 認証トークン',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'SmolLM などの一部のゲートモデル（利用規約への同意が必要なモデル）をダウンロードする際、HuggingFaceのアクセストークン（Read権限）が必要です。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hfTokenController,
                  obscureText: _obscureToken,
                  onChanged: (val) async {
                    await AiBackendService.setHuggingFaceToken(val.trim());
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'HuggingFace Access Token (hf_...)',
                    hintText: 'hf_...',
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureToken ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureToken = !_obscureToken;
                        });
                      },
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text('モデルを選択', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      ...kLocalModels.map((m) => RadioListTile<String>(
        title: Text(m.displayName),
        subtitle: Text('${m.sizeLabel} - ${m.description}'),
        value: m.name,
        groupValue: _selectedModelName,
        onChanged: (v) async {
          if (v == null) return;
          await AiBackendService.setSelectedModelName(v);
          final installed = FlutterGemma.hasActiveModel();
          setState(() {
            _selectedModelName = v;
            _isModelInstalled = installed;
          });
        },
      )),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isDownloading) ...([
              Text('ダウンロード中... ${(_downloadProgress * 100).toStringAsFixed(1)}%'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _downloadProgress),
            ]) else if (_isModelInstalled)
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('${model.displayName} インストール済み'),
                ],
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: Text('${model.displayName} をダウンロード (${model.sizeLabel})'),
                onPressed: _downloadModel,
              ),
          ],
        ),
      ),
    ];
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
                const SizedBox(height: 16),
                if (_user == null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Googleでサインイン'),
                      onPressed: _signInWithGoogle,
                    ),
                  )
                else
                  Column(
                    children: [
                      if (_user!.photoURL != null)
                        CircleAvatar(
                          backgroundImage: NetworkImage(_user!.photoURL!),
                          radius: 40,
                        )
                      else
                        const CircleAvatar(
                          radius: 40,
                          child: Icon(Icons.person, size: 40),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'ログイン中: ${_user!.displayName ?? 'ユーザー名を取得できませんでした'}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('${_user!.email}',
                          style: const TextStyle(fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Text('ユーザーID: ${_user!.uid}',
                          style: const TextStyle(fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Text('登録日: ${_user!.metadata.creationTime}',
                          style: const TextStyle(fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('サインアウト'),
                        style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: _signOut,
                      ),
                    ],
                  ),
                _buildAiBackendSection(),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
