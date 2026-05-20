import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:chat_application/main.dart';
import 'package:chat_application/post.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatScreen extends StatelessWidget {
  final String name;

  const ChatScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
        // tap 可能にするために InkWell を使います。
        InkWell(
          onTap: () {
            // プロフィール画面などへの遷移を追加予定
          },
          child: FirebaseAuth.instance.currentUser?.photoURL != null &&
              FirebaseAuth.instance.currentUser!.photoURL!.isNotEmpty
              ? CircleAvatar(
            backgroundImage: NetworkImage(
              FirebaseAuth.instance.currentUser!.photoURL!,
            ),
            radius: 20,
          )
              : const CircleAvatar(
            radius: 20,
            child: Icon(Icons.person),
          ),
        )
      ],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Post>>(
              // stream プロパティに snapshots() を与えると、コレクションの中のドキュメントをリアルタイムで監視することができます。
              stream:postsReference.orderBy('createdAt').snapshots(),
              // ここで受け取っている snapshot に stream で流れてきたデータが入っています。
              builder: (context, snapshot) {
                // docs には Collection に保存されたすべてのドキュメントが入ります。
                // 取得までには時間がかかるのではじめは null が入っています。
                // null の場合は空配列が代入されるようにしています。
                final docs = snapshot.data?.docs ?? [];
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    // data() に Post インスタンスが入っています。
                    // これは withConverter を使ったことにより得られる恩恵です。
                    // 何もしなければこのデータ型は Map になります。
                    final post = docs[index].data();
                    return Text(post.text);
                  },
                );
              },
            ),
          ),
          TextFormField(
            onFieldSubmitted: (text) {
              //user変数にログイン中のユーザーデータを格納
              final user = FirebaseAuth.instance.currentUser!;

              final posterId = user.uid; // ログイン中のユーザーのID
              final posterName = user.displayName!; // Googleアカウントの名前
              final posterImageUrl = user.photoURL!; // Googleアカウントのアイコンデータ

              // postsReference からランダムなIDのドキュメントリファレンスを作成
              final newDocumentReference = postsReference.doc();

              final newPost = Post(
                text: text,
                createdAt: Timestamp.now(),
                posterName: posterName,
                posterImageUrl: posterImageUrl,
                posterId: posterId,
                reference: newDocumentReference,
              );

              // 先ほど作った newDocumentReference のset関数を実行するとそのドキュメントにデータが保存されます。
              // 引数として Post インスタンスを渡します。
              // 通常は Map しか受け付けませんが、withConverter を使用したことにより Post インスタンスを受け取れるようになります。
              newDocumentReference.set(newPost);
            },
          ),
        ],
      ),
    );
  }
}
