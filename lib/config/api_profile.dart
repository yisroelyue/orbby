import 'package:uuid/uuid.dart';

/// API 协议类型：决定请求/响应格式与认证头（OpenAI 兼容 / Anthropic）。
/// 值域与 agent-runtime 侧 client.ts 的 `platform === 'anthropic'` 判定兼容
/// （Flutter 侧 llm payload 的 platform 字段传的就是这里的值）。
class ApiProtocol {
  ApiProtocol._();

  static const openai = 'openai';
  static const anthropic = 'anthropic';

  static const all = [openai, anthropic];

  static String displayName(String protocol) =>
      protocol == anthropic ? 'Anthropic' : 'OpenAI 兼容';
}

/// 一份 API 配置（一个可独立切换的"服务商"实例）。
/// 用户可自由新增任意多份（内置平台模板只是新增/编辑时的填充预设），
/// 当前激活的那份用于聊天（chat.start 的 llm 快照）与翻译/分析直连。
class ApiProfile {
  ApiProfile({
    String? id,
    this.name = '',
    this.protocol = ApiProtocol.openai,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
  }) : id = id ?? const Uuid().v4();

  /// 唯一标识。新建随机生成；旧格式（platform + apiConfigs）迁移时用
  /// 确定性 id `migrated-<平台key>`——多 engine 并发迁移也生成相同 id 与
  /// 内容，写盘结果等价、无竞态。
  final String id;

  /// 显示名，如 "DeepSeek 官方"、"我的中转站"
  String name;

  /// 协议（[ApiProtocol]）
  String protocol;

  /// Chat API 完整端点（语义同旧配置的 chatUrl）
  String baseUrl;

  String apiKey;

  /// 该配置的默认模型；空 = UI 显示「未设置模型」，
  /// 发送时由 Node 报 configuration incomplete 兜底
  String model;

  factory ApiProfile.fromJson(Map<String, dynamic> json) {
    return ApiProfile(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      protocol: json['protocol'] as String? ?? ApiProtocol.openai,
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
  };

  ApiProfile copy() => ApiProfile(
    id: id,
    name: name,
    protocol: protocol,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
  );
}
