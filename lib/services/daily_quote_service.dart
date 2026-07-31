import 'llm_task.dart';

class DailyQuoteTask extends LlmTask<Map<String, dynamic>> {
  final String type;
  final String country;

  DailyQuoteTask({this.type = '', this.country = ''});

  @override
  String buildSystemPrompt() {
    final typeHint = type.isNotEmpty ? '类型限定为「$type」。' : '可以来自诗词、名言、歌词、歇后语、俚语、短笑话等类型。';
    final countryHint = country.isNotEmpty ? '国家限定为「$country」。' : '可以来自中外古今。';

    return '''
你是一个每日一言生成器。根据要求（如果有）随机选择一条名言佳句。不一定要很大众的，可以避免经常重复。
$typeHint$countryHint


返回 JSON 格式：
{
  "text": "名言内容",
  "author": "作者",
  "source": "出处（书籍/作品名）"
}

如果无法确定作者或出处，对应字段返回空字符串。不要编造不存在的内容。''';
  }

  @override
  String buildUserPrompt() => '给我一条今天的每日一言。';

  @override
  Map<String, dynamic> parseResponse(String response) {
    final data = super.parseResponse(response);
    return {
      'text': data['text']?.toString() ?? '',
      'author': data['author']?.toString() ?? '',
      'source': data['source']?.toString() ?? '',
    };
  }
}

class DailyQuoteService {
  static Future<Map<String, String>> fetchQuote({String type = '', String country = ''}) async {
    final task = DailyQuoteTask(type: type, country: country);
    final data = await task.execute();
    return {
      'text': data['text'] as String? ?? '',
      'author': data['author'] as String? ?? '',
      'source': data['source'] as String? ?? '',
    };
  }
}
