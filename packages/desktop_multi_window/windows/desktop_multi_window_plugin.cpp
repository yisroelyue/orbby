#include "include/desktop_multi_window/desktop_multi_window_plugin.h"
#include "multi_window_plugin_internal.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cstdio>
#include <memory>
#include <string>

#include "flutter_window_wrapper.h"
#include "multi_window_manager.h"
#include "window_channel_plugin.h"

namespace {
  void _dbg(const char* msg) {
    // Use the same directory as the Dart LogService
    const char* home = getenv("USERPROFILE");
    if (!home) home = getenv("HOME");
    std::string path = std::string(home ? home : ".") + "/.orbby/cpp_debug.log";
    FILE* f = fopen(path.c_str(), "a");
    if (f) {
      fprintf(f, "%s\n", msg);
      fclose(f);
    }
  }
}

namespace {

class DesktopMultiWindowPlugin : public flutter::Plugin {
 public:
  DesktopMultiWindowPlugin(FlutterWindowWrapper* window,
                           flutter::PluginRegistrarWindows* registrar);

  ~DesktopMultiWindowPlugin() override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  FlutterWindowWrapper* window_;
  flutter::PluginRegistrarWindows* registrar_;
};

DesktopMultiWindowPlugin::DesktopMultiWindowPlugin(
    FlutterWindowWrapper* window,
    flutter::PluginRegistrarWindows* registrar)
    : window_(window), registrar_(registrar) {
  _dbg("[plugin] DesktopMultiWindowPlugin CONSTRUCTOR");
  auto channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "mixin.one/desktop_multi_window",
          &flutter::StandardMethodCodec::GetInstance());
  _dbg("[plugin] MethodChannel created");
  channel->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
  _dbg("[plugin] SetMethodCallHandler done");

  // Set channel to window for event notifications
  window_->SetChannel(channel);

  // Register WindowChannel plugin for each engine
  WindowChannelPluginRegisterWithRegistrar(registrar);
  _dbg("[plugin] Constructor DONE");
}

DesktopMultiWindowPlugin::~DesktopMultiWindowPlugin() {
   MultiWindowManager::Instance()->RemoveWindow(window_->GetWindowId());
}

void DesktopMultiWindowPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // Check if this is a window-specific method (starts with "window_")
  const auto& method = method_call.method_name();
  if (method.rfind("window_", 0) == 0) {
    auto* arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto window_id = std::get<std::string>(
        arguments->at(flutter::EncodableValue("windowId")));

    auto window = MultiWindowManager::Instance()->GetWindow(window_id);
    if (!window) {
      result->Error("-1", "failed to find target window: " + window_id);
      return;
    }

    window->HandleWindowMethod(method, arguments, std::move(result));
    return;
  }

  if (method == "createWindow") {
    _dbg("[plugin] HandleMethodCall: createWindow");
    auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    auto window_id = MultiWindowManager::Instance()->Create(args);
    result->Success(flutter::EncodableValue(window_id));
    return;
  } else if (method == "getWindowDefinition") {
    _dbg("[plugin] HandleMethodCall: getWindowDefinition CALLED!");
    flutter::EncodableMap definition;
    definition[flutter::EncodableValue("windowId")] =
        flutter::EncodableValue(window_->GetWindowId());
    definition[flutter::EncodableValue("windowArgument")] =
        flutter::EncodableValue(window_->GetWindowArgument());
    _dbg(("[plugin] HandleMethodCall: responding with windowId = " + window_->GetWindowId()).c_str());
    result->Success(flutter::EncodableValue(definition));
    return;
  } else if (method == "getAllWindows") {
    auto windows = MultiWindowManager::Instance()->GetAllWindows();
    result->Success(flutter::EncodableValue(windows));
    return;
  }

  result->NotImplemented();
}

}  // namespace

void DesktopMultiWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  _dbg("[plugin] RegisterWithRegistrar ENTER");
  auto view = FlutterDesktopPluginRegistrarGetView(registrar);
  _dbg(view ? "[plugin] GetView OK" : "[plugin] GetView NULL, fallback to GetViewById");
  if (!view) {
    view = FlutterDesktopPluginRegistrarGetViewById(registrar, 0);
    _dbg(view ? "[plugin] GetViewById(0) OK" : "[plugin] GetViewById(0) ALSO NULL");
  }
  auto hwnd = FlutterDesktopViewGetHWND(view);
  _dbg(hwnd ? "[plugin] HWND valid" : "[plugin] HWND NULL");
  MultiWindowManager::Instance()->AttachFlutterMainWindow(
      GetAncestor(hwnd, GA_ROOT), registrar);
  _dbg("[plugin] RegisterWithRegistrar EXIT");
}

void InternalMultiWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar,
    FlutterWindowWrapper* window) {
  _dbg("[plugin] InternalRegister ENTER");
  auto plugin_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  _dbg(plugin_registrar ? "[plugin] registrar OK" : "[plugin] registrar NULL!");
  auto messenger = plugin_registrar ? plugin_registrar->messenger() : nullptr;
  _dbg(messenger ? "[plugin] messenger OK" : "[plugin] messenger NULL!");
  auto plugin =
      std::make_unique<DesktopMultiWindowPlugin>(window, plugin_registrar);
  plugin_registrar->AddPlugin(std::move(plugin));
  _dbg("[plugin] InternalRegister EXIT - channel should be set up");
}
