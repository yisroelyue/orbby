#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_channel.h>
#include <flutter/encodable_value.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "orbby_plugin_screen_record_plugin.h"

namespace orbby_plugin_screen_record {
namespace test {

namespace {

using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;
using flutter::MethodChannel;
using flutter::EventChannel;
using flutter::StandardMethodCodec;

// Minimal mock binary messenger for testing.
struct MockBinaryMessenger : flutter::BinaryMessenger {
  void Send(const std::string& channel, const uint8_t* message,
            size_t message_size,
            flutter::BinaryReply reply) const override {}
  void SetMessageHandler(const std::string& channel,
                         flutter::BinaryMessageHandler handler) override {}
};

}  // namespace

TEST(OrbbyPluginScreenRecordPlugin, GetPlatformVersion) {
  MockBinaryMessenger messenger;

  auto method_channel =
      std::make_unique<MethodChannel<EncodableValue>>(
          &messenger, "orbby_plugin_screen_record",
          &StandardMethodCodec::GetInstance());

  auto state_channel =
      std::make_unique<EventChannel<EncodableValue>>(
          &messenger, "orbby_plugin_screen_record/state",
          &StandardMethodCodec::GetInstance());

  auto progress_channel =
      std::make_unique<EventChannel<EncodableValue>>(
          &messenger, "orbby_plugin_screen_record/progress",
          &StandardMethodCodec::GetInstance());

  OrbbyPluginScreenRecordPlugin plugin(
      nullptr, std::move(method_channel), std::move(state_channel),
      std::move(progress_channel));

  std::string result_string;
  plugin.HandleMethodCall(
      MethodCall("getPlatformVersion", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&result_string](const EncodableValue* result) {
            result_string = std::get<std::string>(*result);
          },
          nullptr, nullptr));

  EXPECT_TRUE(result_string.rfind("Windows ", 0) == 0);
}

}  // namespace test
}  // namespace orbby_plugin_screen_record
