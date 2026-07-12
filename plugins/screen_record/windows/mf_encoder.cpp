#include "mf_encoder.h"

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <cstring>
#include <iostream>

namespace orbby_plugin_screen_record {

MFEncoder::MFEncoder() = default;

MFEncoder::~MFEncoder() {
  Shutdown();
}

bool MFEncoder::Initialize(int width, int height, int fps, int bitrate,
                           const std::wstring& output_path) {
  Shutdown();

  width_ = width;
  height_ = height;
  fps_ = fps;
  output_path_ = output_path;
  frame_count_ = 0;

  if (!InitMediaFoundation()) {
    return false;
  }

  if (!CreateSinkWriter(output_path_)) {
    Shutdown();
    return false;
  }

  if (!ConfigureEncoding(width_, height_, fps_, bitrate)) {
    Shutdown();
    return false;
  }

  // Pre-allocate NV12 conversion buffers.
  // Y plane: one byte per pixel.
  nv12_y_buffer_ = new (std::nothrow) uint8_t[width_ * height_];
  // UV plane: interleaved UV, 2 bytes per 2x2 block = width * height / 2.
  nv12_uv_buffer_ =
      new (std::nothrow) uint8_t[width_ * height_ / 2];

  if (!nv12_y_buffer_ || !nv12_uv_buffer_) {
    Shutdown();
    return false;
  }

  initialized_ = true;
  return true;
}

bool MFEncoder::InitMediaFoundation() {
  if (mf_initialized_) {
    return true;
  }

  HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET);
  if (FAILED(hr)) {
    std::cerr << "MFEncoder: MFStartup failed. HRESULT: 0x" << std::hex << hr
              << std::endl;
    return false;
  }

  mf_initialized_ = true;
  return true;
}

bool MFEncoder::CreateSinkWriter(const std::wstring& output_path) {
  // Ensure the output directory exists.
  std::wstring dir = output_path;
  size_t last_slash = dir.find_last_of(L"\\/");
  if (last_slash != std::wstring::npos) {
    dir = dir.substr(0, last_slash);
    // Create directory tree, check result.
    HRESULT dir_hr = SHCreateDirectoryExW(nullptr, dir.c_str(), nullptr);
    if (FAILED(dir_hr) && dir_hr != HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS) &&
        dir_hr != HRESULT_FROM_WIN32(ERROR_FILE_EXISTS)) {
      std::cerr << "MFEncoder: Failed to create output directory. HRESULT: 0x"
                << std::hex << dir_hr << std::endl;
      // Continue anyway — maybe the directory already exists.
    }
  }

  // Configure sink writer attributes for MP4 output.
  IMFAttributes* sink_attrs = nullptr;
  HRESULT hr = MFCreateAttributes(&sink_attrs, 2);
  if (SUCCEEDED(hr)) {
    sink_attrs->SetGUID(MF_TRANSCODE_CONTAINERTYPE,
                        MFTranscodeContainerType_MPEG4);
    // Lower latency for real-time recording.
    sink_attrs->SetUINT32(MF_LOW_LATENCY, TRUE);
  }

  hr = MFCreateSinkWriterFromURL(
      output_path.c_str(),
      nullptr,       // no byte stream
      sink_attrs,    // attributes for MP4 container
      &sink_writer_);

  if (sink_attrs) {
    sink_attrs->Release();
  }

  if (FAILED(hr)) {
    std::cerr << "MFEncoder: MFCreateSinkWriterFromURL failed. HRESULT: 0x"
              << std::hex << hr << std::endl;
    std::wcerr << L"  Output path: " << output_path << std::endl;
    return false;
  }

  return true;
}

bool MFEncoder::ConfigureEncoding(int width, int height, int fps,
                                  int bitrate) {
  HRESULT hr;

  // --- Output Media Type (H.264) ---
  // Create this first — AddStream expects the output / container format.
  hr = MFCreateMediaType(&output_media_type_);
  if (FAILED(hr)) {
    std::cerr
        << "MFEncoder: MFCreateMediaType (output) failed. HRESULT: 0x"
        << std::hex << hr << std::endl;
    return false;
  }

  output_media_type_->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  output_media_type_->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  output_media_type_->SetUINT32(MF_MT_INTERLACE_MODE,
                                 MFVideoInterlace_Progressive);
  MFSetAttributeSize(output_media_type_, MF_MT_FRAME_SIZE,
                     static_cast<UINT32>(width),
                     static_cast<UINT32>(height));
  MFSetAttributeRatio(output_media_type_, MF_MT_FRAME_RATE,
                      static_cast<UINT32>(fps), 1);
  MFSetAttributeRatio(output_media_type_, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  output_media_type_->SetUINT32(MF_MT_AVG_BITRATE,
                                 static_cast<UINT32>(bitrate));

  // Add a video stream, using the output type as a hint for the encoder.
  hr = sink_writer_->AddStream(output_media_type_, &stream_index_);
  if (FAILED(hr)) {
    std::cerr << "MFEncoder: AddStream failed. HRESULT: 0x" << std::hex << hr
              << std::endl;
    return false;
  }

  // --- Input Media Type (NV12) ---
  hr = MFCreateMediaType(&input_media_type_);
  if (FAILED(hr)) {
    std::cerr
        << "MFEncoder: MFCreateMediaType (input) failed. HRESULT: 0x"
        << std::hex << hr << std::endl;
    return false;
  }

  input_media_type_->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  input_media_type_->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
  input_media_type_->SetUINT32(MF_MT_INTERLACE_MODE,
                                MFVideoInterlace_Progressive);
  MFSetAttributeSize(input_media_type_, MF_MT_FRAME_SIZE,
                     static_cast<UINT32>(width),
                     static_cast<UINT32>(height));
  MFSetAttributeRatio(input_media_type_, MF_MT_FRAME_RATE,
                      static_cast<UINT32>(fps), 1);
  MFSetAttributeRatio(input_media_type_, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);

  // AVG bitrate.
  input_media_type_->SetUINT32(MF_MT_AVG_BITRATE,
                                static_cast<UINT32>(bitrate));

  // Tell the sink writer the actual format of samples we'll be feeding in.
  hr = sink_writer_->SetInputMediaType(stream_index_, input_media_type_,
                                        nullptr);
  if (FAILED(hr)) {
    std::cerr
        << "MFEncoder: SetInputMediaType failed. HRESULT: 0x"
        << std::hex << hr << std::endl;
    return false;
  }

  // Begin writing.
  hr = sink_writer_->BeginWriting();
  if (FAILED(hr)) {
    std::cerr << "MFEncoder: BeginWriting failed. HRESULT: 0x" << std::hex
              << hr << std::endl;
    return false;
  }

  writing_started_ = true;
  return true;
}

// Static color conversion: BGRA → NV12.
// NV12 format: Y plane (full resolution) followed by interleaved UV plane
// (half resolution, U and V alternating per 2x2 block).
void MFEncoder::ConvertBGRAtoNV12(const uint8_t* bgra, uint8_t* nv12_y,
                                  uint8_t* nv12_uv, int w, int h) {
  // Y plane: one luminance byte per pixel.
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int pixel_offset = (y * w + x) * 4;
      uint8_t B = bgra[pixel_offset];
      uint8_t G = bgra[pixel_offset + 1];
      uint8_t R = bgra[pixel_offset + 2];

      // BT.601 Y calculation.
      // Y = 0.299*R + 0.587*G + 0.114*B
      int Y_val = (66 * R + 129 * G + 25 * B + 128) >> 8;
      Y_val = (Y_val < 0) ? 0 : (Y_val > 255 ? 255 : Y_val);
      nv12_y[y * w + x] = static_cast<uint8_t>(Y_val);
    }
  }

  // UV plane: subsampled 2x2, each block gets one U and one V.
  for (int y = 0; y < h; y += 2) {
    for (int x = 0; x < w; x += 2) {
      // Average the 2x2 block's R, G, B.
      int sum_R = 0, sum_G = 0, sum_B = 0;
      int count = 0;

      for (int dy = 0; dy < 2; dy++) {
        for (int dx = 0; dx < 2; dx++) {
          int px = x + dx;
          int py = y + dy;
          if (px < w && py < h) {
            int offset = (py * w + px) * 4;
            sum_B += bgra[offset];
            sum_G += bgra[offset + 1];
            sum_R += bgra[offset + 2];
            count++;
          }
        }
      }

      int avg_R = sum_R / count;
      int avg_G = sum_G / count;
      int avg_B = sum_B / count;

      // BT.601 U and V calculation.
      // U = -0.169*R - 0.331*G + 0.500*B + 128
      // V =  0.500*R - 0.419*G - 0.081*B + 128
      int U_val = ((-38 * avg_R - 74 * avg_G + 112 * avg_B + 128) >> 8) + 128;
      int V_val = ((112 * avg_R - 94 * avg_G - 18 * avg_B + 128) >> 8) + 128;

      U_val = (U_val < 0) ? 0 : (U_val > 255 ? 255 : U_val);
      V_val = (V_val < 0) ? 0 : (V_val > 255 ? 255 : V_val);

      // Interleaved UV: U, V, U, V...
      int uv_offset = (y / 2) * w + x;
      nv12_uv[uv_offset] = static_cast<uint8_t>(U_val);
      nv12_uv[uv_offset + 1] = static_cast<uint8_t>(V_val);
    }
  }
}

bool MFEncoder::WriteFrame(const uint8_t* bgra_data, int64_t timestamp_ms) {
  if (!initialized_ || !writing_started_) {
    return false;
  }

  // Convert BGRA to NV12 into the combined buffer.
  // NV12 layout: [Y plane: w*h] [UV interleaved: w*h/2].
  ConvertBGRAtoNV12(bgra_data, nv12_y_buffer_, nv12_uv_buffer_, width_,
                    height_);

  // Create a SINGLE IMFMediaBuffer with both Y and UV planes.
  // Media Foundation expects NV12 as one contiguous buffer.
  const uint32_t y_size = width_ * height_;
  const uint32_t uv_size = width_ * height_ / 2;
  const uint32_t total_size = y_size + uv_size;

  IMFMediaBuffer* media_buffer = nullptr;
  HRESULT hr = MFCreateMemoryBuffer(total_size, &media_buffer);
  if (FAILED(hr)) {
    std::cerr << "MFEncoder: MFCreateMemoryBuffer failed. HRESULT: 0x"
              << std::hex << hr << std::endl;
    return false;
  }

  BYTE* buf_data = nullptr;
  hr = media_buffer->Lock(&buf_data, nullptr, nullptr);
  if (FAILED(hr)) {
    media_buffer->Release();
    return false;
  }
  std::memcpy(buf_data, nv12_y_buffer_, y_size);
  std::memcpy(buf_data + y_size, nv12_uv_buffer_, uv_size);
  media_buffer->Unlock();
  media_buffer->SetCurrentLength(total_size);

  // Create IMFSample with the single buffer.
  IMFSample* sample = nullptr;
  hr = MFCreateSample(&sample);
  if (FAILED(hr)) {
    media_buffer->Release();
    return false;
  }

  sample->AddBuffer(media_buffer);
  media_buffer->Release();

  // Set sample timestamp (in 100-nanosecond units for Media Foundation).
  LONGLONG hns_time = timestamp_ms * 10000LL;
  sample->SetSampleTime(hns_time);
  sample->SetSampleDuration(10000000LL / fps_);

  // Write the sample.
  hr = sink_writer_->WriteSample(stream_index_, sample);
  sample->Release();

  if (FAILED(hr)) {
    std::cerr << "MFEncoder: WriteSample failed. HRESULT: 0x" << std::hex
              << hr << std::endl;
    return false;
  }

  frame_count_++;
  return true;
}

bool MFEncoder::Finalize() {
  if (!initialized_) {
    return false;
  }

  HRESULT hr = S_OK;
  if (sink_writer_ && writing_started_) {
    // Only finalize if at least one frame was written.
    if (frame_count_ > 0) {
      hr = sink_writer_->Finalize();
      if (FAILED(hr)) {
        std::cerr << "MFEncoder: Finalize failed. HRESULT: 0x" << std::hex << hr
                  << std::endl;
        // Non-fatal: proceed with cleanup even if Finalize fails.
      }
    }
    writing_started_ = false;
  }

  Shutdown();
  return SUCCEEDED(hr);
}

int64_t MFEncoder::GetFileSize() {
  if (output_path_.empty()) {
    return 0;
  }

  // Do NOT call Flush here — it violates the sink writer contract that
  // forbids WriteSample after Flush without an intervening SendStreamTick
  // or BeginWriting. The file size from disk is sufficient for progress
  // reporting even if slightly behind.

  WIN32_FILE_ATTRIBUTE_DATA file_info;
  if (GetFileAttributesExW(output_path_.c_str(), GetFileExInfoStandard,
                            &file_info)) {
    LARGE_INTEGER size;
    size.LowPart = file_info.nFileSizeLow;
    size.HighPart = file_info.nFileSizeHigh;
    return size.QuadPart;
  }

  return 0;
}

void MFEncoder::Shutdown() {
  if (sink_writer_) {
    sink_writer_->Release();
    sink_writer_ = nullptr;
  }
  if (input_media_type_) {
    input_media_type_->Release();
    input_media_type_ = nullptr;
  }
  if (output_media_type_) {
    output_media_type_->Release();
    output_media_type_ = nullptr;
  }

  delete[] nv12_y_buffer_;
  nv12_y_buffer_ = nullptr;

  delete[] nv12_uv_buffer_;
  nv12_uv_buffer_ = nullptr;

  if (mf_initialized_) {
    MFShutdown();
    mf_initialized_ = false;
  }

  initialized_ = false;
  writing_started_ = false;
  frame_count_ = 0;
  stream_index_ = 0;
}

}  // namespace orbby_plugin_screen_record
