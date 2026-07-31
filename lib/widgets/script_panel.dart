import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/script_item.dart';
import '../services/panel_cache.dart';
import '../services/panel_data_service.dart';
import '../services/script_service.dart';
import 'app_toast.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

/// 脚本头部注释模板说明
const String scriptCommentHint =
    '请添加顶部注释，使用三引号 """ docstring 包裹，内容为纯 JSON，包含 '
    'name（脚本名称）、description（功能描述）、param（参数数组）三个字段；'
    'param 中每个参数对象包含 flag（如 -f, --file）、type（类型:file/str）、'
    'required（是否必填）、description（参数说明）四个字段，'
    'JSON 直接放入 """ 内，不用 # 二次包裹，确保其他程序可直接解析。';

class ScriptPanel extends BasePanel {
  const ScriptPanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.small;

  @override
  String get panelName => 'script';

  @override
  State<ScriptPanel> createState() => _ScriptPanelState();
}

class _ScriptPanelState extends BasePanelState<ScriptPanel> {
  List<ScriptItem> _scripts = [];
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    PanelCache.addListener(_onCacheChanged);
    if (!PanelCache.has('script_items')) {
      setState(() => _loading = true);
      PanelDataService.refreshScripts();
    }
  }

  @override
  void dispose() {
    PanelCache.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() => _loadFromCache();

  void _loadFromCache() {
    final cached = PanelCache.get<List<ScriptItem>>('script_items');
    if (cached != null && mounted) {
      setState(() {
        _scripts = cached;
        _loading = false;
      });
    }
  }

  /// 复制脚本注释模板说明
  void _copyHint() {
    Clipboard.setData(const ClipboardData(text: scriptCommentHint));
    if (mounted) {
      AppToast.show(context, message: '已复制注释模板说明');
    }
  }

  /// 添加脚本：选择文件 → 解析注释 → 复制到脚本库
  Future<void> _openAddDialog() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['py', 'sh', 'bat', 'cmd', 'js'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    setState(() => _adding = true);
    try {
      await ScriptService.addFromPath(path);
      PanelDataService.refreshScripts();
      if (mounted) {
        AppToast.show(context, message: '脚本添加成功');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          message: '添加失败: $e',
          icon: Icons.error_rounded,
          iconColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// 打开运行弹窗
  void _openRunDialog(ScriptItem item) {
    final controllers = <String, TextEditingController>{};
    for (final p in item.params) {
      controllers[p.flag] = TextEditingController();
    }
    final filePaths = <String, String>{};
    String? errorText;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: 460,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 头部：脚本信息
                    Row(
                      children: [
                        _buildScriptIcon(item),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  color: Color(0xFF1F1F1F),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (item.description.isNotEmpty)
                                Text(
                                  item.description,
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 22, color: Colors.grey.shade500),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 参数区
                    if (item.params.isEmpty)
                      Text(
                        '该脚本无需参数',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 13),
                      )
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final p in item.params) ...[
                                _buildParamInput(p, controllers, filePaths),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        ),
                      ),
                    if (errorText != null) ...[
                      const SizedBox(height: 4),
                      Text(errorText!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 13)),
                    ],
                    const SizedBox(height: 12),
                    // 底部按钮
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => _confirmDelete(item),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade400),
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: const Text('删除'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.grey.shade600),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            // 校验必填参数
                            final values = <String, String>{};
                            for (final p in item.params) {
                              final v = p.isFileType
                                  ? (filePaths[p.flag] ?? '')
                                  : controllers[p.flag]!.text.trim();
                              values[p.flag] = v;
                              if (p.required && v.isEmpty) {
                                setDialogState(
                                    () => errorText = '参数 ${p.flag} 为必填项');
                                return;
                              }
                            }
                            Navigator.pop(context);
                            await _runScript(item, values);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5B6EF5),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 10),
                          ),
                          child: const Text('运行'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 单个参数输入控件
  Widget _buildParamInput(
    ScriptParam param,
    Map<String, TextEditingController> controllers,
    Map<String, String> filePaths,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              param.flag,
              style: const TextStyle(
                color: Color(0xFF333333),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (param.required) ...[
              const SizedBox(width: 4),
              const Text('*',
                  style: TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ],
        ),
        if (param.description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(param.description,
              style:
                  TextStyle(color: Colors.grey.shade500, fontSize: 11)),
        ],
        const SizedBox(height: 6),
        if (param.isFileType)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controllers[param.flag],
                  readOnly: true,
                  style: const TextStyle(
                      color: Color(0xFF333333), fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    hintText: '选择文件',
                    hintStyle: TextStyle(
                        color: Colors.grey.shade400, fontSize: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: TextButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles();
                    if (result != null && result.files.isNotEmpty) {
                      final path = result.files.first.path;
                      if (path != null) {
                        filePaths[param.flag] = path;
                        controllers[param.flag]!.text = path;
                      }
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    foregroundColor: const Color(0xFF5B6EF5),
                    backgroundColor:
                        const Color(0xFF5B6EF5).withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text('选择'),
                ),
              ),
            ],
          )
        else
          TextField(
            controller: controllers[param.flag],
            style: const TextStyle(color: Color(0xFF333333), fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.grey.shade50,
              hintText: param.type == 'int' || param.type == 'number'
                  ? '请输入数值'
                  : '请输入内容',
              hintStyle:
                  TextStyle(color: Colors.grey.shade400, fontSize: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
      ],
    );
  }

  /// 确认删除
  Future<void> _confirmDelete(ScriptItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('删除脚本'),
        content: Text('确定删除「${item.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ScriptService.remove(item.id);
      if (mounted) {
        // 关闭运行弹窗
        Navigator.of(context).pop();
        PanelDataService.refreshScripts();
        AppToast.show(context, message: '已删除');
      }
    }
  }

  /// 运行脚本并通过通知发送结果
  Future<void> _runScript(ScriptItem item, Map<String, String> values) async {
    try {
      final result = await Process.run(item.executable, item.buildArgs(values));
      if (!mounted) return;
      if (result.exitCode == 0) {
        final output = (result.stdout as String).trim();
        final msg = output.isNotEmpty
            ? (output.length > 200 ? '${output.substring(0, 200)}...' : output)
            : '执行完毕';
        // 居中 toast 展示执行结果
        AppToast.show(
          context,
          message: msg,
          duration: const Duration(seconds: 4),
        );
      } else {
        final error = (result.stderr as String).trim();
        final msg = error.isNotEmpty
            ? (error.length > 200 ? '${error.substring(0, 200)}...' : error)
            : '执行失败';
        // 居中 toast 展示错误信息
        AppToast.show(
          context,
          message: msg,
          icon: Icons.error_rounded,
          iconColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          message: '执行失败: $e',
          icon: Icons.error_rounded,
          iconColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Row(
          children: [
            Icon(Icons.code_rounded, color: primaryText, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '脚本库',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 注释模板提示按钮
            Tooltip(
              richMessage: const TextSpan(
                children: [
                  TextSpan(
                    text: '点击按钮复制提示给AI，生成符合格式的注释信息\n\n',
                    style: TextStyle(
                      color: Color(0xFF1F1F1F),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: scriptCommentHint,
                    style: TextStyle(
                      color: Color(0xFF444444),
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black.withOpacity(0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              preferBelow: false,
              margin: const EdgeInsets.all(40),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              waitDuration: const Duration(milliseconds: 300),
              child: InteractiveIcon(
                size: 28,
                onTap: _copyHint,
                child: Icon(Icons.info_outline_rounded,
                    color: primaryText.withValues(alpha: 0.5), size: 16),
              ),
            ),
            const SizedBox(width: 4),
            if (_adding)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tertiaryText,
                ),
              )
            else
              InteractiveIcon(
                size: 28,
                onTap: _openAddDialog,
                child: Icon(Icons.add_rounded,
                    color: primaryText.withValues(alpha: 0.5), size: 18),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tertiaryText,
                ),
              ),
            ),
          )
        else if (_scripts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Text(
                '暂无脚本，点击 + 添加',
                style: TextStyle(color: mutedText, fontSize: 13),
              ),
            ),
          )
        else
          Expanded(child: _buildScriptList()),
      ],
    );
  }

  Widget _buildScriptList() {
    return ScrollConfiguration(
      behavior:
          ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        itemCount: _scripts.length,
        itemBuilder: (context, index) =>
            _buildScriptItem(_scripts[index]),
      ),
    );
  }

  Widget _buildScriptItem(ScriptItem item) {
    final isHovered = ValueNotifier<bool>(false);
    return ValueListenableBuilder<bool>(
      valueListenable: isHovered,
      builder: (context, hovered, _) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => isHovered.value = true,
          onExit: (_) => isHovered.value = false,
          child: GestureDetector(
            onTap: () => _openRunDialog(item),
            child: Container(
              key: ValueKey(item.id),
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: hovered ? hoverBg : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  // 脚本图标
                  _buildScriptIcon(item),
                  const SizedBox(width: 8),
                  // 脚本信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: TextStyle(
                              color: primaryText,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.description.isNotEmpty)
                          Text(
                            item.description,
                            style: TextStyle(
                                color: mutedText, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (hovered)
                    Icon(
                      Icons.play_arrow_rounded,
                      size: 18,
                      color: Colors.greenAccent,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScriptIcon(ScriptItem item) {
    final ext = item.scriptPath.split('.').last.toLowerCase();
    IconData icon;
    Color color;

    switch (ext) {
      case 'py':
        icon = Icons.code_rounded;
        color = const Color(0xFF3776AB);
        break;
      case 'sh':
        icon = Icons.terminal_rounded;
        color = const Color(0xFF4EAA25);
        break;
      case 'bat':
      case 'cmd':
        icon = Icons.terminal_rounded;
        color = const Color(0xFF4D4D4D);
        break;
      case 'js':
        icon = Icons.javascript_rounded;
        color = const Color(0xFFF7DF1E);
        break;
      default:
        icon = Icons.code_rounded;
        color = primaryText;
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: color, size: 16),
    );
  }
}
