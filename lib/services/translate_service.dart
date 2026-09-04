// 翻译服务
// 继承 LlmTask，无状态一次性请求，返回 JSON

import 'llm_task.dart';
import 'tencent_translate_service.dart';
import '../config/settings.dart';

abstract interface class TranslationProvider {
  Future<String> translate(String text, {required TranslateLang lang});
}

/// 翻译语言对
enum TranslateLang {
  zhEn('中↔英', '中文', 'English'),
  zhJa('中↔日', '中文', '日本語'),
  zhKo('中↔韩', '中文', '한국어'),
  zhFr('中↔法', '中文', 'Français'),
  zhDe('中↔德', '中文', 'Deutsch'),
  zhEs('中↔西', '中文', 'Español');

  const TranslateLang(this.label, this.sourceName, this.targetName);
  final String label;
  final String sourceName;
  final String targetName;
}

/// 翻译任务
class TranslateTask extends LlmTask<Map<String, dynamic>> {
  final String text;
  final TranslateLang lang;

  TranslateTask({
    required this.text,
    this.lang = TranslateLang.zhEn,
  });

  @override
  String buildSystemPrompt() {
    final toTarget = isChinese(text);
    return '${_directionPrompt(lang, toTarget)}\n\n'
        '请严格以 JSON 格式输出，示例：{"translation":"翻译结果"}\n'
        '不要包含任何额外文字、解释或 Markdown 标记。';
  }

  @override
  String buildUserPrompt() => text;

  @override
  Map<String, dynamic> parseResponse(String response) {
    final result = super.parseResponse(response);
    if (result['translation'] is! String) {
      throw FormatException('翻译结果缺少 translation 字段: $response');
    }
    return result;
  }

  /// 便捷入口：执行翻译并返回翻译文本
  static Future<String> translate(
    String text, {
    TranslateLang lang = TranslateLang.zhEn,
  }) async {
    final task = TranslateTask(text: text, lang: lang);
    final result = await task.execute();
    return result['translation'] as String;
  }

  /// 启发式检测是否为中文：有 CJK 字符且占比 ≥ 拉丁字母
  static bool isChinese(String text) {
    int cjk = 0, latin = 0;
    for (final cp in text.runes) {
      if ((cp >= 0x4E00 && cp <= 0x9FFF) ||
          (cp >= 0x3400 && cp <= 0x4DBF) ||
          (cp >= 0xF900 && cp <= 0xFAFF) ||
          (cp >= 0x3000 && cp <= 0x303F)) {
        cjk++;
      } else if ((cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A)) {
        latin++;
      }
    }
    return cjk > 0 && cjk >= latin;
  }

  /// 根据语言对和检测方向生成提示词
  static String _directionPrompt(TranslateLang lang, bool toTarget) {
    switch (lang) {
      case TranslateLang.zhEn:
        if (toTarget) {
          return 'You are a professional Chinese-to-English translator. '
              'Translate the user\'s text into natural, idiomatic English. '
              'Output ONLY the English translation.';
        }
        return '你是一名专业的英中翻译。将用户输入的英文翻译成自然流畅的简体中文。'
            '只输出中文翻译结果。';
      case TranslateLang.zhJa:
        if (toTarget) {
          return 'あなたはプロの中国語から日本語への翻訳者です。'
              'ユーザーのテキストを自然で idiomatic な日本語に翻訳してください。'
              '日本語の翻訳結果のみを出力してください。';
        }
        return '你是一名专业的日中翻译。将用户输入的日文翻译成自然流畅的简体中文。'
            '只输出中文翻译结果。';
      case TranslateLang.zhKo:
        if (toTarget) {
          return '당신은 전문 중국어-한국어 번역가입니다. '
              '사용자의 텍스트를 자연스럽고 관용적인 한국어로 번역하세요. '
              '한국어 번역 결과만 출력하세요.';
        }
        return '你是一名专业的韩中翻译。将用户输入的韩文翻译成自然流畅的简体中文。'
            '只输出中文翻译结果。';
      case TranslateLang.zhFr:
        if (toTarget) {
          return 'Vous êtes un traducteur professionnel chinois-français. '
              'Traduisez le texte de l\'utilisateur en français naturel et idiomatique. '
              'Ne produisez QUE la traduction française.';
        }
        return '你是一名专业的法中翻译。将用户输入的法文翻译成自然流畅的简体中文。'
            '只输出中文翻译结果。';
      case TranslateLang.zhDe:
        if (toTarget) {
          return 'Sie sind ein professioneller Chinesisch-Deutsch-Übersetzer. '
              'Übersetzen Sie den Text des Benutzers in natürliches, idiomatisches Deutsch. '
              'Geben Sie NUR die deutsche Übersetzung aus.';
        }
        return '你是一名专业的德中翻译。将用户输入的德文翻译成自然流畅的简体中文。'
            '只输出中文翻译结果。';
      case TranslateLang.zhEs:
        if (toTarget) {
          return 'Eres un traductor profesional chino-español. '
              'Traduce el texto del usuario al español natural e idiomático. '
              'Produce SOLO la traducción al español.';
        }
        return '你是一名专业的西中翻译。将用户输入的西班牙文翻译成自然流畅的简体中文。'
            '只输出中文翻译结果。';
    }
  }
}

/// 兼容旧调用的入口类
class TranslateService {
  TranslateService._();

  static Future<String> translate(
    String text, {
    TranslateLang lang = TranslateLang.zhEn,
  }) async {
    try {
      final settings = await SettingsService.load();
      if (settings.translationProvider == 'tencent') {
        return await TencentTranslateService().translate(text, lang: lang);
      }
      return await TranslateTask.translate(text, lang: lang);
    } on FormatException catch (e) {
      throw TranslateException(e.message);
    } on Exception catch (e) {
      throw TranslateException('翻译失败: $e');
    }
  }
}

class TranslateException implements Exception {
  TranslateException(this.message);
  final String message;

  @override
  String toString() => message;
}
