import 'api_profile.dart';

class PlatformInfo {
  const PlatformInfo(this.name, this.key, this.asset);
  final String name;
  final String key;
  final String asset;
}

/// 内置平台预设（模板库）：只用于「新增/编辑 API 配置」时一键填充
/// 名称/协议/端点/默认模型，以及全新安装时的默认配置——用户实际使用的是
/// 自由的 ApiProfile 列表（见 settings.dart），不再按平台各存一份。
class PlatformConfig {
  PlatformConfig._();

  static const platforms = <String, PlatformInfo>{
    'deepseek': PlatformInfo('DeepSeek', 'deepseek', 'assets/png/plugins/deepseek.png'),
    'openai': PlatformInfo('OpenAI', 'openai', 'assets/png/plugins/openai.png'),
    'anthropic': PlatformInfo('Anthropic', 'anthropic', 'assets/png/plugins/anthropic.png'),
    'doubao': PlatformInfo('豆包', 'doubao', 'assets/png/plugins/doubao.png'),
    'mimo': PlatformInfo('小米 MiMo', 'mimo', 'assets/png/plugins/AI.png'),
    'qwen': PlatformInfo('通义千问', 'qwen', 'assets/png/plugins/AI.png'),
    'kimi': PlatformInfo('Kimi', 'kimi', 'assets/png/plugins/AI.png'),
    'zhipu': PlatformInfo('智谱 GLM', 'zhipu', 'assets/png/plugins/AI.png'),
  };

  static String assetPath(String key) {
    return platforms[key]?.asset ?? 'assets/png/plugins/AI.png';
  }

  /// 各平台模板的默认 Chat API 端点
  static String defaultChatUrl(String key) {
    return switch (key) {
      'deepseek' => 'https://api.deepseek.com/v1/chat/completions',
      'openai'   => 'https://api.openai.com/v1/chat/completions',
      'anthropic'=> 'https://api.anthropic.com/v1/messages',
      'doubao'   => 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      'mimo'     => 'https://api.xiaomimimo.com/v1/chat/completions',
      'qwen'     => 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
      'kimi'     => 'https://api.moonshot.cn/v1/chat/completions',
      'zhipu'    => 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      _          => 'https://api.deepseek.com/v1/chat/completions',
    };
  }

  /// 各平台模板的默认模型
  static String defaultChatModel(String key) {
    return switch (key) {
      'deepseek' => 'deepseek-chat',
      'openai'   => 'gpt-3.5-turbo',
      'anthropic'=> 'claude-3-haiku-20240307',
      'doubao'   => 'doubao-lite-32k',
      'mimo'     => 'mimo-mini',
      'qwen'     => 'qwen-turbo',
      'kimi'     => 'moonshot-v1-8k',
      'zhipu'    => 'glm-4-flash',
      _          => 'deepseek-chat',
    };
  }

  /// 平台模板对应的协议（Anthropic 原生，其余 OpenAI 兼容）
  static String templateProtocol(String key) =>
      key == 'anthropic' ? ApiProtocol.anthropic : ApiProtocol.openai;

  /// 按协议返回认证头（Anthropic 用 x-api-key，OpenAI 兼容用 Bearer）
  static Map<String, String> chatAuthHeaders(String protocol, String apiKey) {
    if (protocol == ApiProtocol.anthropic) {
      return {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      };
    }
    return {'Authorization': 'Bearer $apiKey'};
  }
}
