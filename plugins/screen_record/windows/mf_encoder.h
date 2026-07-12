#ifndef MF_ENCODER_H_
#define MF_ENCODER_H_

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <cstdint>
#include <string>

namespace orbby_plugin_screen_record {

/// Encodes BGRA frames to H.264 MP4 using Media Foundation Sink Writer.
///
/// Uses CPU-side BGRA→NV12 color conversion. All Media Foundation
/// initialization and shutdown is handled internally.
class MFEncoder {
 public:
  MFEncoder();
  ~MFEncoder();

  // Non-copyable, non-movable.
  MFEncoder(const MFEncoder&) = delete;
  MFEncoder& operator=(const MFEncoder&) = delete;

  /// Initializes the encoder and creates the output file.
  ///
  /// @param width      Frame width in pixels.
  /// @param height     Frame height in pixels.
  /// @param fps        Frames per second.
  /// @param bitrate    Target bitrate in bits per second.
  /// @param output_path  Full path to the output .mp4 file.
  /// @return true on success.
  bool Initialize(int width, int height, int fps, int bitrate,
                  const std::wstring& output_path);

  /// Writes a single BGRA frame to the output file.
  ///
  /// @param bgra_data   Pointer to BGRA pixel data (width * height * 4 bytes).
  /// @param timestamp_ms  Frame timestamp in milliseconds.
  /// @return true on success.
  bool WriteFrame(const uint8_t* bgra_data, int64_t timestamp_ms);

  /// Finalizes the output file. Must be called to produce a valid MP4.
  /// @return true on success.
  bool Finalize();

  /// Returns the current output file size in bytes, or 0 if unavailable.
  int64_t GetFileSize();

  /// Returns whether the encoder has been initialized.
  bool IsInitialized() const { return initialized_; }

 private:
  /// Converts a BGRA buffer to NV12 format.
  /// @param bgra    Input BGRA data (w * h * 4 bytes).
  /// @param nv12_y  Output Y plane buffer (w * h bytes, caller-allocated).
  /// @param nv12_uv Output UV plane buffer (w * h / 2 bytes, caller-allocated).
  /// @param w       Width in pixels.
  /// @param h       Height in pixels.
  static void ConvertBGRAtoNV12(const uint8_t* bgra, uint8_t* nv12_y,
                                uint8_t* nv12_uv, int w, int h);

  bool InitMediaFoundation();
  bool CreateSinkWriter(const std::wstring& output_path);
  bool ConfigureEncoding(int width, int height, int fps, int bitrate);
  void Shutdown();

  bool initialized_ = false;
  bool mf_initialized_ = false;
  bool writing_started_ = false;

  int width_ = 0;
  int height_ = 0;
  int fps_ = 0;
  int64_t frame_count_ = 0;

  IMFMediaType* input_media_type_ = nullptr;
  IMFMediaType* output_media_type_ = nullptr;
  IMFSinkWriter* sink_writer_ = nullptr;
  DWORD stream_index_ = 0;

  std::wstring output_path_;

  // Pre-allocated NV12 conversion buffers.
  uint8_t* nv12_y_buffer_ = nullptr;
  uint8_t* nv12_uv_buffer_ = nullptr;
};

}  // namespace orbby_plugin_screen_record

#endif  // MF_ENCODER_H_
