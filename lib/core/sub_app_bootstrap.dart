import 'package:orbby/sub_apps/image_handler_app.dart';
import 'package:orbby/sub_apps/json_viewer_app.dart';
import 'package:orbby/sub_apps/markdown_viewer_app.dart';
import 'package:orbby/sub_apps/screen_record_app.dart';

/// 统一引导：导入所有子应用并调用其注册函数。
/// 新增子应用时在此添加 import 和 register 调用。
void bootstrapSubApps() {
  registerImageHandlerApp();
  registerMarkdownViewerApp();
  registerScreenRecordApp();
  registerJsonViewerApp();
}
