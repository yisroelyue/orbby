#ifndef SCREEN_CAPTURE_H_
#define SCREEN_CAPTURE_H_

#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <cstdint>
#include <memory>

namespace orbby_plugin_screen_record {

/// Captures the full desktop screen using DXGI Desktop Duplication API.
///
/// Must be created and used on the same thread. All D3D11/DXGI resources
/// are managed internally.
class ScreenCapture {
 public:
  ScreenCapture();
  ~ScreenCapture();

  // Non-copyable, non-movable.
  ScreenCapture(const ScreenCapture&) = delete;
  ScreenCapture& operator=(const ScreenCapture&) = delete;

  /// Initializes D3D11 device and DXGI desktop duplication.
  /// Must be called before any other method.
  /// Returns true on success.
  bool Initialize();

  /// Releases all DXGI and D3D11 resources.
  void Release();

  /// Returns whether the capture has been successfully initialized.
  bool IsInitialized() const { return initialized_; }

  /// Captures a single frame from the desktop.
  ///
  /// @param out_data  Pointer that will receive the BGRA pixel data.
  ///                  The caller must free this with delete[].
  /// @param out_size  Receives the size of the data buffer in bytes.
  /// @param timeout_ms  Timeout in milliseconds for AcquireNextFrame.
  /// @return true if a frame was successfully captured.
  bool CaptureFrame(uint8_t** out_data, uint32_t* out_size,
                    uint32_t timeout_ms = 100);

  /// Returns the width of the captured screen in pixels.
  int GetScreenWidth() const { return screen_width_; }

  /// Returns the height of the captured screen in pixels.
  int GetScreenHeight() const { return screen_height_; }

 private:
  bool CreateStagingTexture();
  bool CopyDesktopTextureToStaging(ID3D11Texture2D* src_texture);

  bool initialized_ = false;
  int screen_width_ = 0;
  int screen_height_ = 0;

  ID3D11Device* d3d_device_ = nullptr;
  ID3D11DeviceContext* d3d_context_ = nullptr;
  IDXGIOutputDuplication* dxgi_duplication_ = nullptr;
  ID3D11Texture2D* staging_texture_ = nullptr;
};

}  // namespace orbby_plugin_screen_record

#endif  // SCREEN_CAPTURE_H_
