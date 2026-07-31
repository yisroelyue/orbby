#pragma once

#include <cstdint>
#include <iostream>
#include <string>

#include <flutter/encodable_value.h>

struct WindowConfiguration {
  std::string arguments;
  bool hidden_at_launch = false;
  unsigned int initial_width = 800;
  unsigned int initial_height = 600;

  static WindowConfiguration FromEncodableMap(
      const flutter::EncodableMap* map) {
    WindowConfiguration config;
    if (!map) return config;

    try {
      auto it = map->find(flutter::EncodableValue("arguments"));
      if (it != map->end()) {
        config.arguments = std::get<std::string>(it->second);
      }

      it = map->find(flutter::EncodableValue("hiddenAtLaunch"));
      if (it != map->end()) {
        config.hidden_at_launch = std::get<bool>(it->second);
      }

      config.initial_width =
          ReadDimension(map, "initialWidth", config.initial_width);
      config.initial_height =
          ReadDimension(map, "initialHeight", config.initial_height);
    } catch (const std::exception& exception) {
      std::cerr << "Failed to parse WindowConfiguration: "
                << exception.what() << std::endl;
    }

    return config;
  }

 private:
  static unsigned int ReadDimension(const flutter::EncodableMap* map,
                                    const char* key,
                                    unsigned int fallback) {
    const auto it = map->find(flutter::EncodableValue(key));
    if (it == map->end()) return fallback;

    if (const auto* value = std::get_if<int32_t>(&it->second)) {
      return *value > 0 ? static_cast<unsigned int>(*value) : fallback;
    }
    if (const auto* value = std::get_if<int64_t>(&it->second)) {
      return *value > 0 ? static_cast<unsigned int>(*value) : fallback;
    }
    if (const auto* value = std::get_if<double>(&it->second)) {
      return *value > 0 ? static_cast<unsigned int>(*value) : fallback;
    }

    return fallback;
  }
};