import 'package:cloud_firestore/cloud_firestore.dart';

class ChatModel {
  static const typeNormal = 'normal';
  static const typeAiDemo = 'ai_demo';

  ChatModel({
    required this.name,
    required this.avatarUrl,
    required this.lastMessage,
    required this.updatedAt,
    required this.participants,
    required this.reference,
    this.type = typeNormal,
  });

  factory ChatModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final map = snapshot.data() ?? {};
    return ChatModel(
      name: map['name'] ?? '',
      avatarUrl: map['avatarUrl'] ?? '',
      lastMessage: map['lastMessage'] ?? '',
      updatedAt: map['updatedAt'] ?? Timestamp.now(),
      participants: List<String>.from(map['participants'] ?? []),
      reference: snapshot.reference,
      type: map['type'] ?? typeNormal,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'avatarUrl': avatarUrl,
      'lastMessage': lastMessage,
      'updatedAt': updatedAt,
      'participants': participants,
      'type': type,
    };
  }

  final String name;
  final String avatarUrl;
  final String lastMessage;
  final Timestamp updatedAt;
  final List<String> participants;
  final DocumentReference reference;
  final String type;

  bool get isAiDemo => type == typeAiDemo;
}

