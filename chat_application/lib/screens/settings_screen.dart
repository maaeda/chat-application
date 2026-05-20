import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  @override
  void initState() {
    super.initState();
    _initializeGoogleSignIn();
    _auth.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _user = user;
        });
      }
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _user == null
                ? ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('Googleでサインイン'),
                    onPressed: _signInWithGoogle,
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),
                      Text(
                        '${_user!.email}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),

                      const SizedBox(height: 8),
                      Text(
                        'ユーザーID:${_user!.uid}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),

                      const SizedBox(height: 8),
                      Text(
                        '登録日:${_user!.metadata.creationTime}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),

                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('サインアウト'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: _signOut,
                      ),

                    ],
                  ),
      ),
    );
  }
}
