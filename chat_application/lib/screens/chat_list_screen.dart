import 'package:flutter/material.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Chat> chatList = [
      Chat(
        name: "山田 太郎",
        message: "こんにちは！元気ですか？",
        time: "10:30",
        avatarUrl: "https://picsum.photos/seed/1/200",
      ),
      Chat(
        name: "鈴木 花子",
        message: "明日の予定について相談したいです。",
        time: "09:15",
        avatarUrl: "https://picsum.photos/seed/2/200",
      ),
      Chat(
        name: "佐藤 次郎",
        message: "了解しました！",
        time: "昨日",
        avatarUrl: "https://picsum.photos/seed/3/200",
      ),
      Chat(
        name: "田中 美咲",
        message: "写真を送信しました。",
        time: "昨日",
        avatarUrl: "https://picsum.photos/seed/4/200",
      ),
      Chat(
        name: "高橋 健一",
        message: "ありがとうございます。",
        time: "2日前",
        avatarUrl: "https://picsum.photos/seed/5/200",
      ),
            Chat(
        name: "高橋 健一",
        message: "ありがとうございます。",
        time: "2日前",
        avatarUrl: "https://picsum.photos/seed/6/200",
      ),
            Chat(
        name: "高橋 健一",
        message: "ありがとうございます。",
        time: "2日前",
        avatarUrl: "https://picsum.photos/seed/7/200",
      ),
            Chat(
        name: "高橋 健一",
        message: "ありがとうございます。",
        time: "2日前",
        avatarUrl: "https://picsum.photos/seed/8/200",
      ),
            Chat(
        name: "高橋 健一",
        message: "ありがとうございます。",
        time: "2日前",
        avatarUrl: "https://picsum.photos/seed/9/200",
      ),
            Chat(
        name: "高橋 健一",
        message: "ありがとうございます。",
        time: "2日前",
        avatarUrl: "https://picsum.photos/seed/10/200",
      ),
            Chat(
        name: "高橋 健一",
        message: "ありがとうございます。",
        time: "2日前",
        avatarUrl: "https://picsum.photos/seed/5/200",
      ),
            Chat(
        name: "高橋 健一",
        message: "ありがとうございます。",
        time: "2日前",
        avatarUrl: "https://picsum.photos/seed/11/200",
      ),
            Chat(
        name: "高橋 健一",
        message: "ありがとうございます。",
        time: "2日前",
        avatarUrl: "https://picsum.photos/seed/12/200",
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('チャット一覧'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        itemCount: chatList.length,
        itemBuilder: (context, index) {
          final chat = chatList[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundImage: NetworkImage(chat.avatarUrl),
              child: Text(
                chat.name.isNotEmpty ? chat.name[0] : '?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              chat.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              chat.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              chat.time,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(name: chat.name),
                ),
              );
            },
          );
        },
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
