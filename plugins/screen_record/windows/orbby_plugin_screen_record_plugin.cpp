#include "orbby_plugin_screen_record_plugin.h"

#include <windows.h>
#include <VersionHelpers.h>
#include <shlobj.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_channel.h>
#include <flutter/encodable_value.h>

#include <chrono>
#include <memory>
#include <sstream>
#include <string>
#include <thread>

namespace {

// Converts a wide string (UTF-16) to UTF-8 std::string.
std::string WideToUtf8(const std::wstring& wstr) {
  if (wstr.empty()) return {};
  int len = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, nullptr, 0,
                                nullptr, nullptr);
  if (len <= 0) return {};
  std::string result(len, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, &result[0], len, nullptr,
                      nullptr);
  // Remove the null terminator that WideCharToMultiByte includes in the count.
  while (!result.empty() && result.back() == '\0') {
    result.pop_back();
  }
  return result;
}

}  // namespace

namespace orbby_plugin_screen_record {

// ---------------------------------------------------------------------------
// RecordingStateStreamHandler
// ---------------------------------------------------------------------------

void RecordingStateStreamHandler::SendState(const std::string& state) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (sink_) {
    sink_->Success(flutter::EncodableValue(state));
  }
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
RecordingStateStreamHandler::OnListenInternal(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
  SetSink(std::move(events));
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
RecordingStateStreamHandler::OnCancelInternal(
    const flutter::EncodableValue* arguments) {
  SetSink(nullptr);
  return nullptr;
}

// ---------------------------------------------------------------------------
// RecordingProgressStreamHandler
// ---------------------------------------------------------------------------

void RecordingProgressStreamHandler::SendProgress(int64_t duration_ms,
                                                  int64_t file_size_bytes) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (sink_) {
    flutter::EncodableMap map;
    map[flutter::EncodableValue("durationMs")] =
        flutter::EncodableValue(duration_ms);
    map[flutter::EncodableValue("fileSizeBytes")] =
        flutter::EncodableValue(file_size_bytes);
    sink_->Success(flutter::EncodableValue(map));
  }
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
RecordingProgressStreamHandler::OnListenInternal(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
  SetSink(std::move(events));
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
RecordingProgressStreamHandler::OnCancelInternal(
    const flutter::EncodableValue* arguments) {
  SetSink(nullptr);
  return nullptr;
}

// ---------------------------------------------------------------------------
// OrbbyPluginScreenRecordPlugin
// ---------------------------------------------------------------------------

// static
void OrbbyPluginScreenRecordPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto method_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "orbby_plugin_screen_record",
          &flutter::StandardMethodCodec::GetInstance());

  auto state_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "orbby_plugin_screen_record/state",
          &flutter::StandardMethodCodec::GetInstance());

  auto progress_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "orbby_plugin_screen_record/progress",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<OrbbyPluginScreenRecordPlugin>(
      registrar, std::move(method_channel), std::move(state_channel),
      std::move(progress_channel));

  registrar->AddPlugin(std::move(plugin));
}

OrbbyPluginScreenRecordPlugin::OrbbyPluginScreenRecordPlugin(
    flutter::PluginRegistrarWindows* registrar,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel,
    std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> state_channel,
    std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> progress_channel)
    : registrar_(registrar),
      channel_(std::move(channel)),
      state_channel_(std::move(state_channel)),
      progress_channel_(std::move(progress_channel)) {
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        this->HandleMethodCall(call, std::move(result));
      });

  // Create handlers and transfer ownership to the event channels.
  // We keep raw pointers for sending events.
  auto state_handler = std::make_unique<RecordingStateStreamHandler>();
  state_handler_ = state_handler.get();
  state_channel_->SetStreamHandler(std::move(state_handler));

  auto progress_handler = std::make_unique<RecordingProgressStreamHandler>();
  progress_handler_ = progress_handler.get();
  progress_channel_->SetStreamHandler(std::move(progress_handler));
}

OrbbyPluginScreenRecordPlugin::~OrbbyPluginScreenRecordPlugin() {
  // Ensure recording is stopped before destroying.
  if (recording_active_.load()) {
    stop_requested_.store(true);
    if (recording_thread_.joinable()) {
      recording_thread_.join();
    }
  }
  // Note: state_handler_ and progress_handler_ are owned by the channels
  // and will be cleaned up automatically when the channels are destroyed.
}

void OrbbyPluginScreenRecordPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "getPlatformVersion") {
    HandleGetPlatformVersion(std::move(result));
  } else if (method == "isSupported") {
    HandleIsSupported(std::move(result));
  } else if (method == "startRecording") {
    HandleStartRecording(method_call.arguments(), std::move(result));
  } else if (method == "pauseRecording") {
    HandlePauseRecording(std::move(result));
  } else if (method == "resumeRecording") {
    HandleResumeRecording(std::move(result));
  } else if (method == "stopRecording") {
    HandleStopRecording(std::move(result));
  } else if (method == "getRecordingProgress") {
    HandleGetRecordingProgress(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void OrbbyPluginScreenRecordPlugin::HandleGetPlatformVersion(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::ostringstream version_stream;
  version_stream << "Windows ";
  if (IsWindows10OrGreater()) {
    version_stream << "10+";
  } else if (IsWindows8OrGreater()) {
    version_stream << "8";
  } else if (IsWindows7OrGreater()) {
    version_stream << "7";
  }
  result->Success(flutter::EncodableValue(version_stream.str()));
}

void OrbbyPluginScreenRecordPlugin::HandleIsSupported(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // DXGI Desktop Duplication requires Windows 8+.
  // We'll also attempt a quick initialization check.
  bool supported = IsWindows8OrGreater();

  if (supported) {
    // Try to create a temporary screen capture to verify.
    ScreenCapture test_capture;
    supported = test_capture.Initialize();
    test_capture.Release();
  }

  result->Success(flutter::EncodableValue(supported));
}

void OrbbyPluginScreenRecordPlugin::HandleStartRecording(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (recording_active_.load()) {
    result->Error("ALREADY_RECORDING", "A recording is already in progress.");
    return;
  }

  // Parse configuration from arguments.
  int fps = 30;
  int width = 0;
  int height = 0;
  int bitrate = 5'000'000;
  std::string output_path;

  if (arguments && std::holds_alternative<flutter::EncodableMap>(*arguments)) {
    const auto& config = std::get<flutter::EncodableMap>(*arguments);

    auto it = config.find(flutter::EncodableValue("fps"));
    if (it != config.end() && std::holds_alternative<int32_t>(it->second)) {
      fps = std::get<int32_t>(it->second);
    }

    it = config.find(flutter::EncodableValue("width"));
    if (it != config.end() && std::holds_alternative<int32_t>(it->second)) {
      width = std::get<int32_t>(it->second);
    }

    it = config.find(flutter::EncodableValue("height"));
    if (it != config.end() && std::holds_alternative<int32_t>(it->second)) {
      height = std::get<int32_t>(it->second);
    }

    it = config.find(flutter::EncodableValue("bitRate"));
    if (it != config.end() && std::holds_alternative<int32_t>(it->second)) {
      bitrate = std::get<int32_t>(it->second);
    }

    it = config.find(flutter::EncodableValue("outputPath"));
    if (it != config.end() &&
        std::holds_alternative<std::string>(it->second)) {
      output_path = std::get<std::string>(it->second);
    }
  }

  // Initialize screen capture.
  screen_capture_ = std::make_unique<ScreenCapture>();
  if (!screen_capture_->Initialize()) {
    screen_capture_.reset();
    result->Error("CAPTURE_INIT_FAILED",
                  "Failed to initialize screen capture.");
    return;
  }

  // Determine output dimensions.
  int cap_width = screen_capture_->GetScreenWidth();
  int cap_height = screen_capture_->GetScreenHeight();

  if (width > 0 && height > 0) {
    cap_width = width;
    cap_height = height;
  }

  // Clamp FPS.
  if (fps < 1) fps = 1;
  if (fps > 60) fps = 60;

  // Compute output file path.
  output_file_path_ = ComputeOutputPath(
      output_path.empty() ? nullptr : &output_path);

  // Initialize encoder.
  mf_encoder_ = std::make_unique<MFEncoder>();
  if (!mf_encoder_->Initialize(cap_width, cap_height, fps, bitrate,
                                output_file_path_)) {
    screen_capture_->Release();
    screen_capture_.reset();
    mf_encoder_.reset();
    result->Error("ENCODER_INIT_FAILED",
                  "Failed to initialize video encoder.");
    return;
  }

  // Start the recording thread.
  recording_active_.store(true);
  recording_paused_.store(false);
  stop_requested_.store(false);
  recording_start_steady_ = std::chrono::steady_clock::now();
  paused_duration_ms_ = 0;

  recording_thread_ = std::thread(
      &OrbbyPluginScreenRecordPlugin::RecordingThreadFunc, this, fps);

  state_handler_->SendState("recording");

  // Return output path to Dart.
  flutter::EncodableMap response;
  response[flutter::EncodableValue("outputPath")] =
      flutter::EncodableValue(WideToUtf8(output_file_path_));
  result->Success(flutter::EncodableValue(response));
}

void OrbbyPluginScreenRecordPlugin::HandlePauseRecording(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!recording_active_.load()) {
    result->Error("NOT_RECORDING", "No recording is in progress.");
    return;
  }
  if (recording_paused_.load()) {
    result->Error("ALREADY_PAUSED", "Recording is already paused.");
    return;
  }

  recording_paused_.store(true);
  pause_start_steady_ = std::chrono::steady_clock::now();

  state_handler_->SendState("paused");
  result->Success();
}

void OrbbyPluginScreenRecordPlugin::HandleResumeRecording(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!recording_active_.load()) {
    result->Error("NOT_RECORDING", "No recording is in progress.");
    return;
  }
  if (!recording_paused_.load()) {
    result->Error("NOT_PAUSED", "Recording is not paused.");
    return;
  }

  // Accumulate the paused duration.
  auto now = std::chrono::steady_clock::now();
  paused_duration_ms_ +=
      std::chrono::duration_cast<std::chrono::milliseconds>(
          now - pause_start_steady_)
          .count();

  recording_paused_.store(false);
  state_handler_->SendState("recording");
  result->Success();
}

void OrbbyPluginScreenRecordPlugin::HandleStopRecording(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!recording_active_.load()) {
    result->Error("NOT_RECORDING", "No recording is in progress.");
    return;
  }

  state_handler_->SendState("stopping");
  stop_requested_.store(true);

  // Wait for the recording thread to finish.
  if (recording_thread_.joinable()) {
    recording_thread_.join();
  }

  recording_active_.store(false);

  // The recording thread has already finalized the encoder.
  // Use the final file size reported by the recording thread.
  int64_t file_size = final_file_size_bytes_.load(std::memory_order_relaxed);
  if (file_size < 0) {
    // Fallback: recording thread didn't finalize (e.g., no frames captured).
    file_size = last_file_size_bytes_.load(std::memory_order_relaxed);
  }
  mf_encoder_.reset();

  // Release screen capture.
  if (screen_capture_) {
    screen_capture_->Release();
    screen_capture_.reset();
  }

  state_handler_->SendState("idle");

  flutter::EncodableMap response;
  response[flutter::EncodableValue("outputPath")] =
      flutter::EncodableValue(WideToUtf8(output_file_path_));
  response[flutter::EncodableValue("fileSizeBytes")] =
      flutter::EncodableValue(file_size);
  response[flutter::EncodableValue("durationMs")] =
      flutter::EncodableValue(last_duration_ms_.load(std::memory_order_relaxed));

  result->Success(flutter::EncodableValue(response));
}

void OrbbyPluginScreenRecordPlugin::HandleGetRecordingProgress(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!recording_active_.load()) {
    result->Success();
    return;
  }

  int64_t duration_ms = last_duration_ms_.load(std::memory_order_relaxed);
  int64_t file_size = last_file_size_bytes_.load(std::memory_order_relaxed);

  flutter::EncodableMap response;
  response[flutter::EncodableValue("durationMs")] =
      flutter::EncodableValue(duration_ms);
  response[flutter::EncodableValue("fileSizeBytes")] =
      flutter::EncodableValue(file_size);

  result->Success(flutter::EncodableValue(response));
}

void OrbbyPluginScreenRecordPlugin::RecordingThreadFunc(int fps) {
  // Frame interval in milliseconds.
  int64_t frame_interval_ms = 1000 / fps;

  // Use high-resolution clock for timing.
  using Clock = std::chrono::steady_clock;

  auto next_frame_time = Clock::now();

  while (!stop_requested_.load()) {
    // Check if paused.
    if (recording_paused_.load()) {
      // While paused, sleep briefly and check again.
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
      next_frame_time = Clock::now();  // Reset timing when paused.
      continue;
    }

    // Capture a frame.
    uint8_t* frame_data = nullptr;
    uint32_t frame_size = 0;

    bool captured = screen_capture_->CaptureFrame(&frame_data, &frame_size,
                                                    static_cast<uint32_t>(
                                                        frame_interval_ms));

    if (captured && frame_data && mf_encoder_) {
      // Calculate the effective timestamp using only steady_clock.
      auto now = Clock::now();
      int64_t elapsed_ms =
          std::chrono::duration_cast<std::chrono::milliseconds>(
              now - recording_start_steady_)
              .count();
      int64_t effective_ms = elapsed_ms - paused_duration_ms_;
      if (effective_ms < 0) effective_ms = 0;

      // Write at native resolution. The encoder handles the
      // configured dimensions.
      bool write_ok = mf_encoder_->WriteFrame(frame_data, effective_ms);

      // Store progress in atomics (no cross-thread EventChannel calls).
      last_duration_ms_.store(effective_ms, std::memory_order_relaxed);
      if (write_ok) {
        last_file_size_bytes_.store(mf_encoder_->GetFileSize(),
                                    std::memory_order_relaxed);
      }

      delete[] frame_data;
    }

    // If AcquireNextFrame timed out (no new frame), we still might want
    // to write a duplicate frame to maintain FPS. For simplicity, we skip
    // and let the encoder handle it.

    // Frame rate limiting.
    next_frame_time += std::chrono::milliseconds(frame_interval_ms);
    auto now = Clock::now();
    if (next_frame_time > now) {
      std::this_thread::sleep_until(next_frame_time);
    } else {
      // We're falling behind; reset the timer.
      next_frame_time = now;
    }
  }

  // Finalize the encoder on this thread — NOT the platform thread.
  // Finalize can block for a while (flushing encoder, writing moov atom).
  if (mf_encoder_) {
    mf_encoder_->Finalize();
    final_file_size_bytes_.store(mf_encoder_->GetFileSize(),
                                  std::memory_order_relaxed);
  }
}

std::wstring OrbbyPluginScreenRecordPlugin::ComputeOutputPath(
    const std::string* requested_path) {
  if (requested_path && !requested_path->empty()) {
    // Convert UTF-8 to wide string.
    int wide_len = MultiByteToWideChar(CP_UTF8, 0, requested_path->c_str(),
                                        -1, nullptr, 0);
    std::wstring wide_path(wide_len, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, requested_path->c_str(), -1,
                        &wide_path[0], wide_len);
    // Remove null terminator from string.
    wide_path.resize(wide_len - 1);
    return wide_path;
  }

  // Generate default path: %USERPROFILE%\Videos\screen_record_YYYYMMDD_HHMMSS.mp4
  wchar_t videos_path[MAX_PATH];
  HRESULT hr = SHGetFolderPathW(nullptr, CSIDL_MYVIDEO, nullptr,
                                 SHGFP_TYPE_CURRENT, videos_path);
  if (FAILED(hr)) {
    // Fallback to user profile directory.
    wchar_t user_profile[MAX_PATH];
    GetEnvironmentVariableW(L"USERPROFILE", user_profile, MAX_PATH);
    wcscpy_s(videos_path, MAX_PATH, user_profile);
  }

  // Generate timestamp.
  SYSTEMTIME st;
  GetLocalTime(&st);

  wchar_t filename[256];
  swprintf_s(filename, 256,
             L"\\screen_record_%04d%02d%02d_%02d%02d%02d.mp4", st.wYear,
             st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

  return std::wstring(videos_path) + std::wstring(filename);
}

}  // namespace orbby_plugin_screen_record
