import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

enum AiBackend {
  googleAi,
  firebaseAi,
  localLlm,
}

class LocalModelInfo {
  final String name;
  final String displayName;
  final String sizeLabel;
  final String description;
  final String url;
  final ModelType modelType;
  /// HuggingFace のアクセストークンとライセンス同意が必要なモデル
  final bool needsAuth;

  const LocalModelInfo({
    required this.name,
    required this.displayName,
    required this.sizeLabel,
    required this.description,
    required this.url,
    required this.modelType,
    this.needsAuth = false,
  });
}

const List<LocalModelInfo> kLocalModels = [
  LocalModelInfo(
    name: 'gemma3-270m-it',
    displayName: 'Gemma 3 270M',
    sizeLabel: '270M',
    description: 'Googleの最軽量Gemma 3モデル。高速動作。',
    url: 'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.task',
    modelType: ModelType.gemmaIt,
    needsAuth: true,
  ),
  LocalModelInfo(
    name: 'smollm2-135m-it',
    displayName: 'SmolLM2 135M',
    sizeLabel: '135M',
    description: '超軽量・超高速。動作確認用に最適。',
    url: 'https://huggingface.co/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
    modelType: ModelType.llama,
    needsAuth: false,
  ),
  LocalModelInfo(
    name: 'qwen2.5-0.5b-it',
    displayName: 'Qwen2.5 0.5B',
    sizeLabel: '0.5B',
    description: '軽量ながら高品質な応答が可能。',
    url: 'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    modelType: ModelType.qwen,
    needsAuth: false,
  ),
  LocalModelInfo(
    name: 'gemma3-1b-it',
    displayName: 'Gemma 3 1B',
    sizeLabel: '1B',
    description: 'Googleの最新Gemma 3。高精度な日本語対応。',
    url: 'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    modelType: ModelType.gemmaIt,
    needsAuth: true,
  ),
  LocalModelInfo(
    name: 'phi-4-mini-it',
    displayName: 'Phi-4 mini',
    sizeLabel: '3.8B',
    description: 'Microsoftの高性能小型モデル。最高品質。',
    url: 'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.task',
    modelType: ModelType.phi,
    needsAuth: false,
  ),
];

class AiBackendService {
  static const _kBackendKey = 'ai_backend';
  static const _kModelNameKey = 'ai_model_name';
  static const _kHfTokenKey = 'hf_token';

  static Future<AiBackend> getBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_kBackendKey);
    if (val != null && val >= 0 && val < AiBackend.values.length) {
      return AiBackend.values[val];
    }
    return AiBackend.googleAi;
  }

  static Future<void> setBackend(AiBackend backend) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBackendKey, backend.index);
  }

  static Future<String> getSelectedModelName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kModelNameKey) ?? kLocalModels.first.name;
  }

  static Future<void> setSelectedModelName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModelNameKey, name);
  }

  static Future<String> getHuggingFaceToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kHfTokenKey) ?? '';
  }

  static Future<void> setHuggingFaceToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHfTokenKey, token);
  }

  static LocalModelInfo getModelByName(String name) {
    return kLocalModels.firstWhere(
      (m) => m.name == name,
      orElse: () => kLocalModels.first,
    );
  }

  /// ローカルLLMモデルが利用可能か確認し、必要に応じてロードする。
  ///
  /// アプリ再起動後、FlutterGemma.initialize() だけではモデルはメモリに
  /// ロードされない（hasActiveModel() == false）。
  /// installModel().fromNetwork().install() を再度呼ぶことで、
  /// ディスク上のモデルファイルを再登録してアクティブにする。
  /// ファイルが既に存在する場合、再ダウンロードは発生しない。
  static Future<bool> ensureLocalModelReady() async {
    // 既にアクティブならOK
    if (FlutterGemma.hasActiveModel()) return true;

    // 選択中のモデルを取得
    final modelName = await getSelectedModelName();
    final model = getModelByName(modelName);
    final fileId = model.url.split('/').last;

    // ディスク上にインストールされているかチェック
    final isInstalled = await FlutterGemma.isModelInstalled(fileId);
    debugPrint('LocalLLM check: model=$modelName, fileId=$fileId, '
        'installed=$isInstalled, active=${FlutterGemma.hasActiveModel()}');

    if (!isInstalled) return false;

    // インストール済みだがアクティブでない → モデルを再登録してロードする
    try {
      debugPrint('LocalLLM: モデルを再登録・ロード中... (${model.displayName})');
      await FlutterGemma.installModel(
        modelType: model.modelType,
      ).fromNetwork(model.url).install();
      debugPrint('LocalLLM: モデルのロード完了 (${model.displayName})');
      return true;
    } catch (e) {
      debugPrint('LocalLLM: モデルのロードに失敗: $e');
      return false;
    }
  }

  /// アプリ起動時にローカルLLMバックエンドが選択されていれば
  /// モデルを自動ロードする。main() から呼び出す。
  static Future<void> loadLocalModelOnStartup() async {
    try {
      final backend = await getBackend();
      if (backend != AiBackend.localLlm) {
        debugPrint('LocalLLM: バックエンドがローカルLLMではないためスキップ');
        return;
      }

      final ready = await ensureLocalModelReady();
      if (ready) {
        debugPrint('LocalLLM: 起動時の自動ロード完了');
      } else {
        debugPrint('LocalLLM: モデルが未インストールのためスキップ');
      }
    } catch (e) {
      // 起動をブロックしないよう、エラーは握りつぶす
      debugPrint('LocalLLM: 起動時の自動ロードでエラー (非致命的): $e');
    }
  }
}
