import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/api_profile.dart';
import '../config/platform.dart';

/// 输入框右下角模型标签的切换浮层 controller：持有配置列表快照与激活项，
/// 拉取激活配置的模型列表、维护键盘选中项。纯逻辑组件（与
/// CommandPaletteController 同模式），切换配置/选择模型的保存落盘由宿主经
/// 回调完成；键盘事件由宿主在主输入框接管层分发（↑/↓/Enter/Esc）。
class ModelPickerController extends ChangeNotifier {
  /// 与输入区的模型标签共享的 TapRegion 组：浮层展开时点击标签不算
  /// "外部点击"（交给标签自身 toggle 收起），点其他区域由浮层的
  /// onTapOutside 收起。
  final Object tapRegionGroup = Object();

  bool _visible = false;
  bool get visible => _visible;

  bool _loading = false;
  bool get loading => _loading;

  /// 拉取失败的错误文案（浮层内红字提示；过滤输入框仍可手动输入模型名）
  String? _error;
  String? get error => _error;

  List<String> _models = const [];

  /// 当前模型（列表项打勾）；拉取结果不含它时插到首位——自定义模型名也能对上号
  String _currentModel = '';

  int _selectedIndex = 0;

  /// 配置列表快照与激活 id（open 时由宿主传入，切 Chip 时更新；
  /// 落盘动作经宿主的 onSwitchProfile 回调，controller 只管 UI 状态）
  List<ApiProfile> _profiles = const [];
  String _activeProfileId = '';

  /// 当前激活配置（profiles 空时兜底 null）
  ApiProfile? get activeProfile {
    for (final p in _profiles) {
      if (p.id == _activeProfileId) return p;
    }
    return _profiles.isEmpty ? null : _profiles.first;
  }

  /// 配置列表快照（Chip 行渲染用）
  List<ApiProfile> get profiles => List.unmodifiable(_profiles);

  /// 激活配置 id
  String get activeProfileId => _activeProfileId;

  // 结果缓存：同一协议 + 端点 + Key 在 TTL 内直接复用，避免每次展开都请求
  String? _cacheKey;
  List<String>? _cached;
  DateTime _cacheAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _cacheTtl = Duration(minutes: 5);

  /// 防竞态：只应用最新一次拉取的结果（展开后关掉又立刻展开等场景）
  int _fetchToken = 0;

  /// 全部模型（含插到首位的当前模型）
  List<String> get models => List.unmodifiable(_models);

  /// 当前模型
  String get currentModel => _currentModel;

  /// 键盘选中项下标（相对 [models]）
  int get selectedIndex => _selectedIndex;

  /// 展开浮层并拉取激活配置的模型列表（命中缓存时直接展示）
  Future<void> open({
    required List<ApiProfile> profiles,
    required String activeProfileId,
  }) async {
    _profiles = profiles;
    _activeProfileId = activeProfileId;
    _selectedIndex = 0;
    _error = null;
    _visible = true;
    _syncCurrentModel();
    notifyListeners();
    await _load(useCache: true);
  }

  /// 切换激活配置（点 Chip）：重置选中项、重拉新配置的模型列表。
  /// 落盘由宿主回调处理，controller 只更新自身状态
  Future<void> switchProfile(String id) async {
    if (id == _activeProfileId) return;
    _activeProfileId = id;
    _selectedIndex = 0;
    _error = null;
    _syncCurrentModel();
    notifyListeners();
    await _load(useCache: true);
  }

  /// 刷新按钮：跳过缓存重新拉取
  Future<void> reload() async {
    if (_loading) return;
    await _load(useCache: false);
  }

  /// 收起浮层（焦点归还等收尾由宿主的 onDismiss 回调处理）
  void close() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  void movePrevious() => _move(-1);

  void moveNext() => _move(1);

  void _move(int delta) {
    if (_models.isEmpty) return;
    _selectedIndex = (_selectedIndex + delta) % _models.length;
    notifyListeners();
  }

  /// 确认（Enter / 点击行）：返回选中的模型名；列表为空返回 null
  String? confirmSelection() {
    if (_models.isEmpty) return null;
    return _models[_selectedIndex.clamp(0, _models.length - 1)];
  }

  /// 激活配置的 model 即"当前模型"（空则空，列表不额外打勾）
  void _syncCurrentModel() {
    _currentModel = activeProfile?.model.trim() ?? '';
  }

  Future<void> _load({required bool useCache}) async {
    final profile = activeProfile;
    if (profile == null) return;
    final key =
        '${profile.protocol}|${profile.baseUrl}|${profile.apiKey}';
    if (useCache &&
        _cacheKey == key &&
        _cached != null &&
        DateTime.now().difference(_cacheAt) < _cacheTtl) {
      _applyModels(_cached!);
      return;
    }
    final token = ++_fetchToken;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final models = await fetchPlatformModels(
        protocol: profile.protocol,
        baseUrl: profile.baseUrl,
        apiKey: profile.apiKey,
      );
      if (token != _fetchToken) return;
      _cacheKey = key;
      _cached = models;
      _cacheAt = DateTime.now();
      _applyModels(models);
    } catch (e) {
      if (token != _fetchToken) return;
      _models = const [];
      _error = '模型列表拉取失败：$e';
      _selectedIndex = 0;
      notifyListeners();
    } finally {
      if (token == _fetchToken) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void _applyModels(List<String> models) {
    // 当前模型不在列表（自定义模型名）时插到首位，保证打勾项可见
    if (_currentModel.isNotEmpty && !models.contains(_currentModel)) {
      _models = [_currentModel, ...models];
    } else {
      _models = models;
    }
    _selectedIndex = 0;
    notifyListeners();
  }
}

/// 拉取配置的模型列表：GET {models 端点}，认证头按协议（Anthropic 用
/// x-api-key，OpenAI 兼容用 Bearer，见 [PlatformConfig.chatAuthHeaders]）。
/// OpenAI 兼容与 Anthropic 的响应都是 `{data: [{id: …}]}` 结构。
Future<List<String>> fetchPlatformModels({
  required String protocol,
  required String baseUrl,
  required String apiKey,
}) async {
  final url = _modelsUrlFromChatUrl(baseUrl);
  final headers = PlatformConfig.chatAuthHeaders(protocol, apiKey);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(Uri.parse(url));
    headers.forEach((name, value) => request.headers.set(name, value));
    final response = await request.close().timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException('模型列表请求超时'),
    );
    final raw = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(raw);
    final data = json is Map ? json['data'] : null;
    if (data is! List) {
      throw const FormatException('响应不是模型列表');
    }
    return data
        .map((e) => e is Map ? e['id'] : null)
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  } finally {
    client.close();
  }
}

/// Chat API 端点 → 模型列表端点：`…/chat/completions`（OpenAI 兼容）与
/// `…/messages`（Anthropic）替换为 `…/models`；其余形态（自定义中转站的
/// `…/v1` 等）按 OpenAI 兼容惯例追加 `/models`。
String _modelsUrlFromChatUrl(String chatUrl) {
  var url = chatUrl.trim().split('?').first;
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  for (final suffix in const ['/chat/completions', '/messages']) {
    if (url.endsWith(suffix)) {
      return '${url.substring(0, url.length - suffix.length)}/models';
    }
  }
  return '$url/models';
}
