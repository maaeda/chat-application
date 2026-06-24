import 'package:flutter/material.dart';
import 'package:chat_application/services/ai_text_transform_service.dart';

/// AI変換結果のプレビュー/確認ダイアログの返却値
enum TransformPreviewAction {
  /// 変換後テキストを入力欄にセットする
  apply,

  /// 別のスタイルでやり直す
  retry,

  /// キャンセル（元のテキストに戻す）
  cancel,
}

/// AI変換結果を確認するためのダイアログ
class AiTransformPreviewDialog extends StatelessWidget {
  final String originalText;
  final String transformedText;
  final TransformStyleInfo styleInfo;

  const AiTransformPreviewDialog({
    super.key,
    required this.originalText,
    required this.transformedText,
    required this.styleInfo,
  });

  /// ダイアログを表示し、ユーザーのアクションを返す
  static Future<TransformPreviewAction?> show(
    BuildContext context, {
    required String originalText,
    required String transformedText,
    required TransformStyleInfo styleInfo,
  }) {
    return showDialog<TransformPreviewAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AiTransformPreviewDialog(
        originalText: originalText,
        transformedText: transformedText,
        styleInfo: styleInfo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final cardBg = isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade100;
    final transformedBg = isDark
        ? colorScheme.primary.withValues(alpha: 0.15)
        : colorScheme.primary.withValues(alpha: 0.08);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ヘッダー
              Row(
                children: [
                  Text(styleInfo.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${styleInfo.name}に変換',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // 閉じるボタン
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () =>
                        Navigator.of(context).pop(TransformPreviewAction.cancel),
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 32),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // スクロール可能なテキスト比較エリア
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 変換前テキスト
                      Text(
                        '変換前',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          originalText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: Colors.grey.withValues(alpha: 0.5),
                          ),
                        ),
                      ),

                      // 矢印
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Icon(
                            Icons.arrow_downward_rounded,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ),
                      ),

                      // 変換後テキスト
                      Text(
                        '変換後',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: transformedBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          transformedText,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // アクションボタン
              Row(
                children: [
                  // キャンセル
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(TransformPreviewAction.cancel),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('キャンセル'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // やり直す
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(TransformPreviewAction.retry),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('やり直す'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 適用
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(TransformPreviewAction.apply),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('適用'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
