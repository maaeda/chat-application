import 'package:flutter/foundation.dart';
import 'package:firebase_ai/firebase_ai.dart' as firebase_ai;
import 'package:google_generative_ai/google_generative_ai.dart' as google_ai;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'ai_backend_service.dart';

/// テキスト変換スタイルの定義
enum TransformStyle {
  casual,
  polite,
  business,
  gentle,
  summarize,
  aiCharacter,
  butler,
  teacher,
}

/// 各スタイルの表示情報を保持するクラス
class TransformStyleInfo {
  final TransformStyle style;
  final String emoji;
  final String name;
  final String description;

  const TransformStyleInfo({
    required this.style,
    required this.emoji,
    required this.name,
    required this.description,
  });
}

/// 利用可能な変換スタイル一覧
const List<TransformStyleInfo> kTransformStyles = [
  TransformStyleInfo(
    style: TransformStyle.casual,
    emoji: '🎉',
    name: 'カジュアル',
    description: 'フランクで親しみやすい表現に',
  ),
  TransformStyleInfo(
    style: TransformStyle.polite,
    emoji: '🙇',
    name: '丁寧',
    description: '敬語を使った丁寧な表現に',
  ),
  TransformStyleInfo(
    style: TransformStyle.business,
    emoji: '💼',
    name: 'ビジネス',
    description: 'ビジネスメールのような表現に',
  ),
  TransformStyleInfo(
    style: TransformStyle.gentle,
    emoji: '🌸',
    name: 'やさしい',
    description: '柔らかく優しい表現に',
  ),
  TransformStyleInfo(
    style: TransformStyle.summarize,
    emoji: '📝',
    name: '要約',
    description: '短く簡潔にまとめる',
  ),
  TransformStyleInfo(
    style: TransformStyle.aiCharacter,
    emoji: '🤖',
    name: 'AI風',
    description: 'ロボットっぽい口調に',
  ),
  TransformStyleInfo(
    style: TransformStyle.butler,
    emoji: '🎩',
    name: '執事風',
    description: '丁重な執事の口調に',
  ),
  TransformStyleInfo(
    style: TransformStyle.teacher,
    emoji: '👨‍🏫',
    name: '先生風',
    description: '教師のような口調に',
  ),
];

class AiTextTransformService {
  /// スタイルに応じたプロンプトを生成する
  static String _buildPrompt(String text, TransformStyle style) {
    final styleInstruction = switch (style) {
      TransformStyle.casual =>
        'フランクでカジュアルな口調に変換してください。タメ口で、親しみやすく、絵文字を少し使っても構いません。',
      TransformStyle.polite =>
        '丁寧語・敬語を使った上品で丁寧な表現に変換してください。「です・ます」調を使用してください。',
      TransformStyle.business =>
        'ビジネスメールに適したフォーマルな表現に変換してください。敬語を使い、簡潔で要点を押さえた表現にしてください。',
      TransformStyle.gentle =>
        '柔らかく優しい表現に変換してください。相手を気遣う言葉を使い、温かみのある文章にしてください。',
      TransformStyle.summarize =>
        '元の意味を保ちながら、できるだけ短く簡潔に要約してください。核心だけを残してください。',
      TransformStyle.aiCharacter =>
        'ロボット・AI風の口調に変換してください。「〜デス」「〜マス」「計算完了」「処理中」のようなカタカナ交じりの機械的な口調にしてください。',
      TransformStyle.butler =>
        '執事・バトラー風の丁重な口調に変換してください。「お嬢様/旦那様」への話し方のように、非常に丁重で格式高い表現にしてください。「かしこまりました」「〜でございます」などを使ってください。',
      TransformStyle.teacher =>
        '学校の先生風の口調に変換してください。「〜だよ」「〜しましょう」「いいですか？」のような教師らしい話し方にしてください。',
    };

    return '''
あなたはテキスト変換アシスタントです。
以下のルールに従って、ユーザーのメッセージを変換してください。

ルール:
1. $styleInstruction
2. 変換後のテキストのみを返してください。説明や補足は一切不要です。
3. 元のメッセージの意味を変えないでください。
4. Markdownの記法は使わないでください。

変換対象のメッセージ:
$text

変換後:''';
  }

  /// ローカルLLMなどの小型モデル向けに、簡素化した Few-shot プロンプトを生成する
  static String _buildFewShotPrompt(String text, TransformStyle style) {
    final (instruction, inputExample, outputExample) = switch (style) {
      TransformStyle.casual => (
          'カジュアルな口調（タメ口・親しみやすい表現）に変換してください。',
          '今日は雨が降っています。',
          '今日は雨だねー。',
        ),
      TransformStyle.polite => (
          'です・ます調の丁寧な敬語表現に変換してください。',
          '今日は雨が降っている。',
          '今日は雨が降っています。',
        ),
      TransformStyle.business => (
          'ビジネスメールに適した丁寧で簡潔なフォーマル表現に変換してください。',
          '今日雨が降ってるから遅れる。',
          '本日は降雨のため、到着が遅れる見込みです。何卒ご容赦ください。',
        ),
      TransformStyle.gentle => (
          '柔らかく優しい、相手を気遣う温かみのある表現に変換してください。',
          '今日は雨が降っています。',
          '今日は雨が降っていますね。足元に気をつけてお出かけください。',
        ),
      TransformStyle.summarize => (
          '元の意味を保ちつつ、できるだけ短く簡潔に要約してください。',
          '今日は雨が降っていて、傘を忘れてしまったのでずぶ濡れになってしまいました。',
          '雨の中、傘を忘れて濡れてしまった。',
        ),
      TransformStyle.aiCharacter => (
          'ロボット・AI風のカタカナ交じりの機械的な口調に変換してください。',
          '今日は雨が降っています。',
          'キョウハ 雨ガ 降ッテイマス。',
        ),
      TransformStyle.butler => (
          '「お嬢様/旦那様」に語りかける非常に丁寧な執事口調に変換してください。',
          '今日は雨が降っています。',
          '旦那様、本日は雨が降っております。お出かけの際はお気をつけくださいませ。',
        ),
      TransformStyle.teacher => (
          '学校の先生が優しく教え諭すような口調に変換してください。',
          '今日は雨が降っています。',
          '今日は雨が降っていますね。みんな、傘を持ってきましたか？',
        ),
    };

    return '''
指示: $instruction
入力: $inputExample
出力: $outputExample
入力: $text
出力:''';
  }

  /// テキストをAIで変換する
  static Future<String> transformText(
    String text,
    TransformStyle style,
  ) async {
    if (text.trim().isEmpty) {
      throw Exception('変換するテキストがありません');
    }

    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    final backend = await AiBackendService.getBackend();
    final effectiveBackend = (backend == AiBackend.googleAi && apiKey.isEmpty)
        ? AiBackend.firebaseAi
        : backend;

    String? result;

    switch (effectiveBackend) {
      case AiBackend.googleAi:
        final prompt = _buildPrompt(text, style);
        final model = google_ai.GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: apiKey,
        );
        final response = await model.generateContent([
          google_ai.Content.text(prompt),
        ]);
        result = response.text?.trim();

      case AiBackend.firebaseAi:
        final prompt = _buildPrompt(text, style);
        final model = firebase_ai.FirebaseAI.googleAI().generativeModel(
          model: 'gemini-2.5-flash',
        );
        final response = await model.generateContent([
          firebase_ai.Content.text(prompt),
        ]);
        result = response.text?.trim();

      case AiBackend.localLlm:
        final prompt = _buildFewShotPrompt(text, style);
        final isReady = await AiBackendService.ensureLocalModelReady();
        if (!isReady) {
          throw Exception('ローカルLLMモデルが未インストールです。設定画面からダウンロードしてください。');
        }
        final inferenceModel = await FlutterGemma.getActiveModel(
          maxTokens: 1024,
        );
        final session = await inferenceModel.createSession();
        await session.addQueryChunk(Message(text: prompt, isUser: true));
        result = await session.getResponse();
        await session.close();
        result = result.trim();
    }

    // 余計なマークダウンや引用符を除去
    if (result != null && result.isNotEmpty) {
      result = result
          .replaceAll(RegExp(r'^```.*$', multiLine: true), '')
          .replaceAll(RegExp(r'^[「」]'), '')
          .replaceAll(RegExp(r'[「」]$'), '')
          .replaceAll(RegExp(r'^"'), '')
          .replaceAll(RegExp(r'"$'), '')
          .trim();
    }

    if (result == null || result.isEmpty) {
      throw Exception('変換結果が空です。もう一度お試しください。');
    }

    debugPrint('AI Transform result: $result');
    return result;
  }
}
