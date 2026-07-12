#ifndef FLUTTER_PLUGIN_ORBBY_PLUGIN_IMAGE_PROCESSER_PLUGIN_H_
#define FLUTTER_PLUGIN_ORBBY_PLUGIN_IMAGE_PROCESSER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace orbby_plugin_image_processer {

class OrbbyPluginImageProcesserPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  OrbbyPluginImageProcesserPlugin();

  virtual ~OrbbyPluginImageProcesserPlugin();

  // Disallow copy and assign.
  OrbbyPluginImageProcesserPlugin(const OrbbyPluginImageProcesserPlugin&) = delete;
  OrbbyPluginImageProcesserPlugin& operator=(const OrbbyPluginImageProcesserPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace orbby_plugin_image_processer

#endif  // FLUTTER_PLUGIN_ORBBY_PLUGIN_IMAGE_PROCESSER_PLUGIN_H_
