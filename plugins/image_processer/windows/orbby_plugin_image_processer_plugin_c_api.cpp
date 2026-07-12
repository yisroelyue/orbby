#include "include/orbby_plugin_image_processer/orbby_plugin_image_processer_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "orbby_plugin_image_processer_plugin.h"

void OrbbyPluginImageProcesserPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  orbby_plugin_image_processer::OrbbyPluginImageProcesserPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
