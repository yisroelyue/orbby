#ifndef FLUTTER_PLUGIN_ORBBY_PLUGIN_SCREEN_RECORD_PLUGIN_H_
#define FLUTTER_PLUGIN_ORBBY_PLUGIN_SCREEN_RECORD_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "screen_capture.h"
#include "mf_encoder.h"

namespace orbby_plugin_screen_record {

/// Event channel handler for recording state changes.
class RecordingStateStreamHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  void SetSink(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
    std::lock_guard<std::mutex> lock(mutex_);
    sink_ = std::move(sink);
  }

  void SendState(const std::string& state);

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override;

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(
      const flutter::EncodableValue* arguments) override;

 private:
  std::mutex mutex_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
};

/// Event channel handler for recording progress updates.
class RecordingProgressStreamHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  void SetSink(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
    std::lock_guard<std::mutex> lock(mutex_);
    sink_ = std::move(sink);
  }

  void SendProgress(int64_t duration_ms, int64_t file_size_bytes);

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override;

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(
      const flutter::EncodableValue* arguments) override;

 private:
  std::mutex mutex_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
};

/// The main plugin class for screen recording on Windows.
class OrbbyPluginScreenRecordPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  OrbbyPluginScreenRecordPlugin(
      flutter::PluginRegistrarWindows* registrar,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel,
      std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> state_channel,
      std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> progress_channel);

  virtual ~OrbbyPluginScreenRecordPlugin();

  // Disallow copy and assign.
  OrbbyPluginScreenRecordPlugin(const OrbbyPluginScreenRecordPlugin&) = delete;
  OrbbyPluginScreenRecordPlugin& operator=(const OrbbyPluginScreenRecordPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  // Method handlers.
  void HandleGetPlatformVersion(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleIsSupported(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleStartRecording(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandlePauseRecording(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleResumeRecording(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleStopRecording(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleGetRecordingProgress(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The recording loop that runs on a separate thread.
  void RecordingThreadFunc(int fps);

  // Computes the output file path.
  std::wstring ComputeOutputPath(const std::string* requested_path);

  flutter::PluginRegistrarWindows* registrar_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> state_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> progress_channel_;

  // Channels own the handlers via SetStreamHandler; we keep raw pointers.
  RecordingStateStreamHandler* state_handler_ = nullptr;
  RecordingProgressStreamHandler* progress_handler_ = nullptr;

  // Screen capture and encoding.
  std::unique_ptr<ScreenCapture> screen_capture_;
  std::unique_ptr<MFEncoder> mf_encoder_;

  // Recording thread control.
  std::thread recording_thread_;
  std::atomic<bool> recording_active_{false};
  std::atomic<bool> recording_paused_{false};
  std::atomic<bool> stop_requested_{false};

  // Recording start time for duration calculation.
  // Use steady_clock time points to avoid cross-clock mismatch with the
  // recording thread's steady_clock-based timing.
  std::chrono::steady_clock::time_point recording_start_steady_;
  std::chrono::steady_clock::time_point pause_start_steady_;
  int64_t paused_duration_ms_ = 0;

  // Progress tracking (written by recording thread, read by platform thread).
  std::atomic<int64_t> last_duration_ms_{0};
  std::atomic<int64_t> last_file_size_bytes_{0};
  std::atomic<int64_t> final_file_size_bytes_{-1};  // -1 = not yet finalized

  std::wstring output_file_path_;
};

}  // namespace orbby_plugin_screen_record

#endif  // FLUTTER_PLUGIN_ORBBY_PLUGIN_SCREEN_RECORD_PLUGIN_H_
