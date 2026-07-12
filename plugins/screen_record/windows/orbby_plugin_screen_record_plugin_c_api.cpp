#include "include/orbby_plugin_screen_record/orbby_plugin_screen_record_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "orbby_plugin_screen_record_plugin.h"

void OrbbyPluginScreenRecordPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  orbby_plugin_screen_record::OrbbyPluginScreenRecordPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
