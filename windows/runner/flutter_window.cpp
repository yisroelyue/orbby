#include "flutter_window.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <optional>
#include <shellapi.h>
#include <vector>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kWindowShapeChannelName[] = "orbby_window_shape";
constexpr char kSetRoundedRegionMethod[] = "setRoundedRegion";
constexpr char kClearRoundedRegionMethod[] = "clearRoundedRegion";
constexpr char kRadiusArgument[] = "radius";

constexpr char kDropChannelName[] = "orbby_file_drop";
constexpr char kHotkeyChannelName[] = "orbby_hotkey";

constexpr int kHotkeyIdToggleMenu = 1;
constexpr int kHotkeyIdOpenSettings = 2;

using WindowShapeChannel = flutter::MethodChannel<flutter::EncodableValue>;
using DropChannel = flutter::MethodChannel<flutter::EncodableValue>;
using HotkeyChannel = flutter::MethodChannel<flutter::EncodableValue>;

std::vector<std::unique_ptr<WindowShapeChannel>> g_window_shape_channels;
std::vector<std::unique_ptr<DropChannel>> g_drop_channels;
std::unique_ptr<HotkeyChannel> g_hotkey_channel;

double GetNumberArgument(const flutter::EncodableValue& value,
                         double fallback) {
  if (const auto* double_value = std::get_if<double>(&value)) {
    return *double_value;
  }
  if (const auto* int_value = std::get_if<int32_t>(&value)) {
    return static_cast<double>(*int_value);
  }
  if (const auto* long_value = std::get_if<int64_t>(&value)) {
    return static_cast<double>(*long_value);
  }
  return fallback;
}

bool SetRoundedWindowRegion(HWND hwnd, double logical_radius) {
  if (!hwnd) {
    return false;
  }

  if (logical_radius <= 0) {
    return SetWindowRgn(hwnd, nullptr, TRUE) != 0;
  }

  RECT bounds;
  if (!GetWindowRect(hwnd, &bounds)) {
    return false;
  }

  const int width = bounds.right - bounds.left;
  const int height = bounds.bottom - bounds.top;
  if (width <= 0 || height <= 0) {
    return false;
  }

  UINT dpi = GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = USER_DEFAULT_SCREEN_DPI;
  }

  const int radius =
      static_cast<int>(logical_radius * dpi / USER_DEFAULT_SCREEN_DPI);
  const int diameter = radius * 2;
  HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1, diameter,
                                   diameter);
  if (!region) {
    return false;
  }

  if (SetWindowRgn(hwnd, region, TRUE) == 0) {
    DeleteObject(region);
    return false;
  }

  return true;
}

void RegisterWindowShapeChannel(flutter::BinaryMessenger* messenger,
                                HWND hwnd) {
  auto channel = std::make_unique<WindowShapeChannel>(
      messenger, kWindowShapeChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [hwnd](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == kSetRoundedRegionMethod) {
          double radius = 0;
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            const auto radius_it =
                arguments->find(flutter::EncodableValue(kRadiusArgument));
            if (radius_it != arguments->end()) {
              radius = GetNumberArgument(radius_it->second, radius);
            }
          }

          if (SetRoundedWindowRegion(hwnd, radius)) {
            result->Success(flutter::EncodableValue(true));
          } else {
            result->Error("set_window_region_failed",
                          "Failed to set rounded window region.");
          }
          return;
        }

        if (call.method_name() == kClearRoundedRegionMethod) {
          if (SetWindowRgn(hwnd, nullptr, TRUE) != 0) {
            result->Success(flutter::EncodableValue(true));
          } else {
            result->Error("clear_window_region_failed",
                          "Failed to clear rounded window region.");
          }
          return;
        }

        result->NotImplemented();
      });

  g_window_shape_channels.emplace_back(std::move(channel));
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }

  // IMPORTANT: SetChildContent must be called BEFORE RegisterPlugins.
  // desktop_multi_window's registration (DesktopMultiWindowPluginRegisterWithRegistrar)
  // calls FlutterDesktopPluginRegistrarGetView to obtain the HWND. In release/AOT
  // mode the Flutter engine defers view association until SetChildContent is called,
  // so calling RegisterPlugins first causes GetView to return NULL and the
  // mixin.one/desktop_multi_window channel to never be registered.
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  RegisterPlugins(flutter_controller_->engine());
  RegisterWindowShapeChannel(flutter_controller_->engine()->messenger(),
                             GetHandle());

  // Register file-drop channel so the pet window can receive dragged files.
  auto drop_channel = std::make_unique<DropChannel>(
      flutter_controller_->engine()->messenger(), kDropChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  drop_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) { result->NotImplemented(); });
  g_drop_channels.emplace_back(std::move(drop_channel));

  // Enable native file drag-and-drop on this window.
  DragAcceptFiles(GetHandle(), TRUE);

  // Register global hotkey: Alt + ~ (backtick key above Tab)
  RegisterHotKey(GetHandle(), kHotkeyIdToggleMenu, MOD_ALT, VK_OEM_3);
  // Register global hotkey: Alt + Ctrl + ~
  RegisterHotKey(GetHandle(), kHotkeyIdOpenSettings, MOD_ALT | MOD_CONTROL, VK_OEM_3);

  // Create hotkey channel to notify Flutter of hotkey presses.
  g_hotkey_channel = std::make_unique<HotkeyChannel>(
      flutter_controller_->engine()->messenger(), kHotkeyChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  g_hotkey_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) { result->NotImplemented(); });

  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    RegisterPlugins(registry);

    // desktop_multi_window creates windows with WS_OVERLAPPEDWINDOW which
    // includes title bar and system buttons. Strip them to keep the window
    // frameless so the acrylic/blur effect renders cleanly.
    HWND hwnd = GetAncestor(
        flutter_view_controller->view()->GetNativeWindow(), GA_ROOT);
    RegisterWindowShapeChannel(registry->messenger(), hwnd);
    LONG style = GetWindowLong(hwnd, GWL_STYLE);
    style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX |
               WS_MAXIMIZEBOX | WS_SYSMENU);
    SetWindowLong(hwnd, GWL_STYLE, style);
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOZORDER | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  UnregisterHotKey(GetHandle(), kHotkeyIdToggleMenu);
  UnregisterHotKey(GetHandle(), kHotkeyIdOpenSettings);
  g_hotkey_channel = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_HOTKEY: {
      if (g_hotkey_channel) {
        if (wparam == kHotkeyIdToggleMenu) {
          g_hotkey_channel->InvokeMethod(
              "toggle_menu", std::make_unique<flutter::EncodableValue>());
        } else if (wparam == kHotkeyIdOpenSettings) {
          g_hotkey_channel->InvokeMethod(
              "open_settings", std::make_unique<flutter::EncodableValue>());
        }
      }
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_DROPFILES: {
      HDROP hDrop = reinterpret_cast<HDROP>(wparam);
      UINT fileCount = DragQueryFileW(hDrop, 0xFFFFFFFF, nullptr, 0);

      flutter::EncodableList fileList;
      for (UINT i = 0; i < fileCount; i++) {
        UINT pathLength = DragQueryFileW(hDrop, i, nullptr, 0);
        std::wstring filePath(pathLength + 1, L'\0');
        DragQueryFileW(hDrop, i, filePath.data(),
                       static_cast<UINT>(filePath.size()));
        filePath.resize(pathLength);

        // Convert wide string to UTF-8.
        int utf8Len = WideCharToMultiByte(CP_UTF8, 0, filePath.c_str(), -1,
                                          nullptr, 0, nullptr, nullptr);
        if (utf8Len > 0) {
          std::string utf8Path(utf8Len, '\0');
          WideCharToMultiByte(CP_UTF8, 0, filePath.c_str(), -1,
                              utf8Path.data(), utf8Len, nullptr, nullptr);
          utf8Path.resize(utf8Len - 1);  // strip null terminator
          fileList.push_back(flutter::EncodableValue(utf8Path));
        }
      }
      DragFinish(hDrop);

      if (!g_drop_channels.empty()) {
        g_drop_channels[0]->InvokeMethod(
            "filesDropped",
            std::make_unique<flutter::EncodableValue>(fileList));
      }
      return 0;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
