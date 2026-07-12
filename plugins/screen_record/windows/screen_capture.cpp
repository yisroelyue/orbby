#include "screen_capture.h"

#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <dxgi1_2.h>
#include <cstring>
#include <iostream>

namespace orbby_plugin_screen_record {

ScreenCapture::ScreenCapture() = default;

ScreenCapture::~ScreenCapture() {
  Release();
}

bool ScreenCapture::Initialize() {
  Release();

  // Create D3D11 device with BGRA support for DXGI interop.
  D3D_FEATURE_LEVEL feature_levels[] = {
      D3D_FEATURE_LEVEL_11_1,
      D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0,
  };

  UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
#ifdef _DEBUG
  flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

  HRESULT hr = D3D11CreateDevice(
      nullptr,                     // default adapter
      D3D_DRIVER_TYPE_HARDWARE,    // hardware driver
      nullptr,                     // no software rasterizer
      flags,
      feature_levels,
      ARRAYSIZE(feature_levels),
      D3D11_SDK_VERSION,
      &d3d_device_,
      nullptr,                     // actual feature level (don't care)
      &d3d_context_);

  if (FAILED(hr)) {
    // Try without debug layer
    flags &= ~D3D11_CREATE_DEVICE_DEBUG;
    hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
                           feature_levels, ARRAYSIZE(feature_levels),
                           D3D11_SDK_VERSION, &d3d_device_, nullptr,
                           &d3d_context_);
  }

  if (FAILED(hr)) {
    // Try WARP (software) as last resort
    hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags,
                           feature_levels, ARRAYSIZE(feature_levels),
                           D3D11_SDK_VERSION, &d3d_device_, nullptr,
                           &d3d_context_);
  }

  if (FAILED(hr)) {
    std::cerr << "ScreenCapture: Failed to create D3D11 device. HRESULT: 0x"
              << std::hex << hr << std::endl;
    return false;
  }

  // Get DXGI device from D3D11 device.
  IDXGIDevice* dxgi_device = nullptr;
  hr = d3d_device_->QueryInterface(__uuidof(IDXGIDevice),
                                    reinterpret_cast<void**>(&dxgi_device));
  if (FAILED(hr)) {
    std::cerr << "ScreenCapture: Failed to get DXGI device. HRESULT: 0x"
              << std::hex << hr << std::endl;
    Release();
    return false;
  }

  // Get DXGI adapter.
  IDXGIAdapter* dxgi_adapter = nullptr;
  hr = dxgi_device->GetAdapter(&dxgi_adapter);
  dxgi_device->Release();
  if (FAILED(hr)) {
    std::cerr << "ScreenCapture: Failed to get DXGI adapter. HRESULT: 0x"
              << std::hex << hr << std::endl;
    Release();
    return false;
  }

  // Get the primary output (monitor).
  IDXGIOutput* dxgi_output = nullptr;
  hr = dxgi_adapter->EnumOutputs(0, &dxgi_output);
  dxgi_adapter->Release();
  if (FAILED(hr)) {
    std::cerr << "ScreenCapture: Failed to enumerate outputs. HRESULT: 0x"
              << std::hex << hr << std::endl;
    Release();
    return false;
  }

  // Get IDXGIOutput1 for desktop duplication.
  IDXGIOutput1* dxgi_output1 = nullptr;
  hr = dxgi_output->QueryInterface(__uuidof(IDXGIOutput1),
                                    reinterpret_cast<void**>(&dxgi_output1));
  dxgi_output->Release();
  if (FAILED(hr)) {
    std::cerr
        << "ScreenCapture: Failed to get IDXGIOutput1. HRESULT: 0x"
        << std::hex << hr << std::endl;
    Release();
    return false;
  }

  // Create desktop duplication.
  hr = dxgi_output1->DuplicateOutput(d3d_device_, &dxgi_duplication_);
  dxgi_output1->Release();
  if (FAILED(hr)) {
    std::cerr
        << "ScreenCapture: Failed to duplicate output. HRESULT: 0x"
        << std::hex << hr << std::endl;
    Release();
    return false;
  }

  // Get the desktop description for dimensions.
  DXGI_OUTDUPL_DESC dup_desc;
  dxgi_duplication_->GetDesc(&dup_desc);
  screen_width_ = static_cast<int>(dup_desc.ModeDesc.Width);
  screen_height_ = static_cast<int>(dup_desc.ModeDesc.Height);

  // Handle rotated displays — swap width/height if rotated 90 or 270 degrees.
  if (dup_desc.Rotation == DXGI_MODE_ROTATION_ROTATE90 ||
      dup_desc.Rotation == DXGI_MODE_ROTATION_ROTATE270) {
    std::swap(screen_width_, screen_height_);
  }

  // Create the staging texture for CPU readback.
  if (!CreateStagingTexture()) {
    Release();
    return false;
  }

  initialized_ = true;
  return true;
}

void ScreenCapture::Release() {
  if (staging_texture_) {
    staging_texture_->Release();
    staging_texture_ = nullptr;
  }
  if (dxgi_duplication_) {
    dxgi_duplication_->Release();
    dxgi_duplication_ = nullptr;
  }
  if (d3d_context_) {
    d3d_context_->Release();
    d3d_context_ = nullptr;
  }
  if (d3d_device_) {
    d3d_device_->Release();
    d3d_device_ = nullptr;
  }
  initialized_ = false;
  screen_width_ = 0;
  screen_height_ = 0;
}

bool ScreenCapture::CreateStagingTexture() {
  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = screen_width_;
  desc.Height = screen_height_;
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.SampleDesc.Quality = 0;
  desc.Usage = D3D11_USAGE_STAGING;
  desc.BindFlags = 0;
  desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  desc.MiscFlags = 0;

  HRESULT hr = d3d_device_->CreateTexture2D(&desc, nullptr, &staging_texture_);
  if (FAILED(hr)) {
    std::cerr << "ScreenCapture: Failed to create staging texture. HRESULT: 0x"
              << std::hex << hr << std::endl;
    return false;
  }

  return true;
}

bool ScreenCapture::CopyDesktopTextureToStaging(
    ID3D11Texture2D* src_texture) {
  d3d_context_->CopyResource(staging_texture_, src_texture);
  return true;
}

bool ScreenCapture::CaptureFrame(uint8_t** out_data, uint32_t* out_size,
                                 uint32_t timeout_ms) {
  if (!initialized_) {
    return false;
  }

  *out_data = nullptr;
  *out_size = 0;

  IDXGIResource* desktop_resource = nullptr;
  DXGI_OUTDUPL_FRAME_INFO frame_info = {};

  HRESULT hr = dxgi_duplication_->AcquireNextFrame(
      timeout_ms, &frame_info, &desktop_resource);

  if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
    // No new frame available within the timeout. This is normal.
    return false;
  }

  if (hr == DXGI_ERROR_ACCESS_LOST) {
    // Desktop duplication interface lost (e.g., UAC prompt, resolution change).
    // The caller should re-initialize.
    std::cerr << "ScreenCapture: DXGI access lost, needs reinitialization."
              << std::endl;
    return false;
  }

  if (FAILED(hr)) {
    std::cerr << "ScreenCapture: AcquireNextFrame failed. HRESULT: 0x"
              << std::hex << hr << std::endl;
    dxgi_duplication_->ReleaseFrame();
    return false;
  }

  // Query the desktop texture from the DXGI resource.
  ID3D11Texture2D* desktop_texture = nullptr;
  hr = desktop_resource->QueryInterface(
      __uuidof(ID3D11Texture2D),
      reinterpret_cast<void**>(&desktop_texture));
  desktop_resource->Release();

  if (FAILED(hr)) {
    std::cerr << "ScreenCapture: Failed to get desktop texture. HRESULT: 0x"
              << std::hex << hr << std::endl;
    dxgi_duplication_->ReleaseFrame();
    return false;
  }

  // Copy the desktop texture to our staging texture.
  CopyDesktopTextureToStaging(desktop_texture);
  desktop_texture->Release();

  // Release the frame immediately — we have our copy.
  dxgi_duplication_->ReleaseFrame();

  // Map the staging texture to read pixels.
  D3D11_MAPPED_SUBRESOURCE mapped = {};
  hr = d3d_context_->Map(staging_texture_, 0, D3D11_MAP_READ, 0, &mapped);
  if (FAILED(hr)) {
    std::cerr << "ScreenCapture: Failed to map staging texture. HRESULT: 0x"
              << std::hex << hr << std::endl;
    return false;
  }

  // Calculate buffer size: BGRA = 4 bytes per pixel.
  uint32_t data_size = screen_width_ * screen_height_ * 4;
  uint8_t* buffer = new (std::nothrow) uint8_t[data_size];
  if (!buffer) {
    d3d_context_->Unmap(staging_texture_, 0);
    return false;
  }

  // Copy row by row (handle potential stride differences).
  uint32_t row_size = screen_width_ * 4;
  uint8_t* dest = buffer;
  const uint8_t* src = static_cast<const uint8_t*>(mapped.pData);
  for (int y = 0; y < screen_height_; y++) {
    std::memcpy(dest, src, row_size);
    dest += row_size;
    src += mapped.RowPitch;
  }

  d3d_context_->Unmap(staging_texture_, 0);

  *out_data = buffer;
  *out_size = data_size;
  return true;
}

}  // namespace orbby_plugin_screen_record
