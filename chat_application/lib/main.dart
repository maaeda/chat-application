import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'screens/chat_list_screen.dart';
import 'screens/settings_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'firebase_options.dart';
import 'post.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/chat_model.dart';
import 'package:chat_application/services/ai_backend_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Firebase App Check の初期化（Android のみ）
  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
    );
  }
  // FlutterGemma の初期化（ローカルLLM機能の事前準備）
  final hfToken = await AiBackendService.getHuggingFaceToken();
  await FlutterGemma.initialize(
    huggingFaceToken: hfToken.isNotEmpty ? hfToken : null,
  );
  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chat Application',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  // 各タブの画面
  static const List<Widget> _pages = <Widget>[
    ChatListScreen(),
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'チャット'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

// chats collection reference with ChatModel converter
final chatsReference = FirebaseFirestore.instance.collection('chats').withConverter<ChatModel>(
  fromFirestore: (snapshot, _) => ChatModel.fromFirestore(snapshot),
  toFirestore: (value, _) => value.toMap(),
);

// helper to get posts collection reference for a given chat
CollectionReference<Post> postsReferenceFor(String chatId) =>
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('posts')
        .withConverter<Post>(
          fromFirestore: (snapshot, _) => Post.fromFirestore(snapshot),
          toFirestore: (value, _) => value.toMap(),
        );


