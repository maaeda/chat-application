import 'package:cloud_firestore/cloud_firestore.dart';

class ChatModel {
  ChatModel({
    required this.name,
    required this.avatarUrl,
    required this.lastMessage,
    required this.updatedAt,
    required this.participants,
    required this.reference,
  });

  factory ChatModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final map = snapshot.data() ?? {};
    return ChatModel(
      name: map['name'] ?? '',
      avatarUrl: map['avatarUrl'] ?? '',
      lastMessage: map['lastMessage'] ?? '',
      updatedAt: map['updatedAt'] ?? Timestamp.now(),
      participants: List<String>.from(map['participants'] ?? []),
      reference: snapshot.reference,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'avatarUrl': avatarUrl,
      'lastMessage': lastMessage,
      'updatedAt': updatedAt,
      'participants': participants,
    };
  }

  final String name;
  final String avatarUrl;
  final String lastMessage;
  final Timestamp updatedAt;
  final List<String> participants;
  final DocumentReference reference;
}

