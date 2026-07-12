class PlatformInfo {
  const PlatformInfo(this.name, this.key, this.asset);
  final String name;
  final String key;
  final String asset;
}

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

  static String defaultBalanceUrl(String key) {
    return switch (key) {
      'deepseek' => 'https://api.deepseek.com/user/balance',
      'openai' => 'https://api.openai.com/v1/usage',
      'anthropic' => 'https://api.anthropic.com/v1/usage',
      'doubao' => 'https://ark.cn-beijing.volces.com/api/v3/usage',
      'mimo' => 'https://api.mimo.ai/v1/usage',
      'qwen' => 'https://dashscope.aliyuncs.com/compatible-mode/v1/usage',
      'kimi' => 'https://api.moonshot.cn/v1/usage',
      'zhipu' => 'https://open.bigmodel.cn/api/paas/v4/usage',
      _ => 'https://api.deepseek.com/user/balance',
    };
  }

  static String assetPath(String key) {
    return platforms[key]?.asset ?? 'assets/png/plugins/AI.png';
  }

  /// 各平台 Chat API 默认端点
  static String defaultChatUrl(String key) {
    return switch (key) {
      'deepseek' => 'https://api.deepseek.com/v1/chat/completions',
      'openai'   => 'https://api.openai.com/v1/chat/completions',
      'anthropic'=> 'https://api.anthropic.com/v1/messages',
      'doubao'   => 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      'mimo'     => 'https://api.mimo.ai/v1/chat/completions',
      'qwen'     => 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
      'kimi'     => 'https://api.moonshot.cn/v1/chat/completions',
      'zhipu'    => 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      _          => 'https://api.deepseek.com/v1/chat/completions',
    };
  }

  /// 各平台默认翻译模型（轻量、快速、便宜）
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

  /// 返回认证头 Map（Anthropic 用 x-api-key，其他用 Authorization: Bearer）
  static Map<String, String> chatAuthHeaders(String key, String apiKey) {
    if (key == 'anthropic') {
      return {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      };
    }
    return {'Authorization': 'Bearer $apiKey'};
  }

  /// 是否为 Anthropic 平台（请求/响应格式不同）
  static bool isAnthropicPlatform(String key) => key == 'anthropic';
}
