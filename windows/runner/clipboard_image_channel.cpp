#include "clipboard_image_channel.h"

#include <windows.h>
#include <shellapi.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdio>
#include <cstring>
#include <cwctype>
#include <string>
#include <vector>

namespace clipboard_image {
namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Channel = flutter::MethodChannel<EncodableValue>;

constexpr char kChannelName[] = "orbby_clipboard_image";
constexpr char kReadImageMethod[] = "readImage";

// COM init guard: initializes COM for this thread if not yet initialized
// (in any mode) and balances it on scope exit.
class ComScope {
 public:
  ComScope() : owns_(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) {}
  ~ComScope() {
    if (owns_) {
      CoUninitialize();
    }
  }

 private:
  bool owns_;
};

// Returns true when the path has an extension that may be attached to chat:
// images plus plain-text files and PDF. Unsupported types fall back to normal
// text paste. The Dart layer owns the final mime whitelist.
bool IsSupportedFileExtension(const std::wstring& path) {
  const size_t dot = path.find_last_of(L'.');
  if (dot == std::wstring::npos) {
    return false;
  }
  std::wstring ext = path.substr(dot + 1);
  for (wchar_t& c : ext) {
    c = static_cast<wchar_t>(::towlower(c));
  }
  return ext == L"png" || ext == L"jpg" || ext == L"jpeg" || ext == L"webp" ||
         ext == L"gif" || ext == L"bmp" || ext == L"txt" || ext == L"md" ||
         ext == L"markdown" || ext == L"csv" || ext == L"log" || ext == L"json" ||
         ext == L"yaml" || ext == L"yml" || ext == L"xml" || ext == L"html" ||
         ext == L"htm" || ext == L"pdf" || ext == L"dart" || ext == L"js" ||
         ext == L"ts" || ext == L"py" || ext == L"java" || ext == L"kt" ||
         ext == L"c" || ext == L"h" || ext == L"cpp" || ext == L"cs" ||
         ext == L"go" || ext == L"rs" || ext == L"sh" || ext == L"bat" ||
         ext == L"ini" || ext == L"cfg";
}

std::wstring MakeTempPngPath() {
  wchar_t temp_dir[MAX_PATH] = {};
  const DWORD length = GetTempPathW(MAX_PATH, temp_dir);
  if (length == 0 || length >= MAX_PATH) {
    return L"";
  }
  wchar_t name[48] = {};
  swprintf_s(name, L"orbby_clip_%llu.png", static_cast<unsigned long long>(GetTickCount64()));
  return std::wstring(temp_dir) + name;
}

// Pixel layout of a clipboard DIB (parsed from the BITMAPINFO header).
struct DibLayout {
  const uint8_t* bits;
  size_t bits_size;
  LONG width;
  LONG height;
  bool top_down;  // biHeight < 0
  WORD bit_count;
};

bool ParseDibLayout(const void* dib, size_t dib_size, DibLayout* out) {
  if (dib_size < sizeof(BITMAPINFOHEADER)) {
    return false;
  }
  auto* header = reinterpret_cast<const BITMAPINFOHEADER*>(dib);
  if (header->biSize < sizeof(BITMAPINFOHEADER) || header->biSize > dib_size) {
    return false;
  }
  const LONG height = header->biHeight < 0 ? -header->biHeight : header->biHeight;
  // Only uncompressed 24/32bpp is supported; paletted and RLE formats are not.
  if (header->biWidth <= 0 || height <= 0 || header->biWidth > 16384 || height > 16384) {
    return false;
  }
  if ((header->biBitCount != 24 && header->biBitCount != 32) ||
      (header->biCompression != BI_RGB && header->biCompression != BI_BITFIELDS)) {
    return false;
  }
  // Bits start after the header plus the color table / masks: with the legacy
  // BITMAPINFOHEADER + BI_BITFIELDS the three RGB masks follow the header;
  // with the V5 header the masks are embedded inside it.
  size_t offset = header->biSize;
  if (header->biCompression == BI_BITFIELDS &&
      header->biSize == sizeof(BITMAPINFOHEADER)) {
    offset += 3 * sizeof(DWORD);
  }
  const size_t src_stride =
      ((static_cast<size_t>(header->biWidth) * header->biBitCount + 31) / 32) * 4;
  if (dib_size < offset + src_stride * static_cast<size_t>(height)) {
    return false;
  }
  out->bits = reinterpret_cast<const uint8_t*>(dib) + offset;
  out->bits_size = dib_size - offset;
  out->width = header->biWidth;
  out->height = height;
  out->top_down = header->biHeight < 0;
  out->bit_count = header->biBitCount;
  return true;
}

// Expands DIB pixels row by row into top-down BGRA. Alpha from clipboard
// sources is often unreliable; force opaque when all 32bpp alpha bytes are 0.
bool ExtractBgraFromDib(const DibLayout& dib, std::vector<uint8_t>* bgra) {
  const size_t dst_stride = static_cast<size_t>(dib.width) * 4;
  const size_t src_stride =
      ((static_cast<size_t>(dib.width) * dib.bit_count + 31) / 32) * 4;
  const size_t src_row_bytes =
      dib.bit_count == 32 ? dst_stride : static_cast<size_t>(dib.width) * 3;
  bgra->assign(dst_stride * dib.height, 0);
  bool has_alpha = false;
  for (LONG y = 0; y < dib.height; ++y) {
    const size_t src_row =
        static_cast<size_t>(dib.top_down ? y : (dib.height - 1 - y)) * src_stride;
    if (src_row + src_row_bytes > dib.bits_size) {
      return false;
    }
    const uint8_t* src = dib.bits + src_row;
    uint8_t* dst = bgra->data() + static_cast<size_t>(y) * dst_stride;
    if (dib.bit_count == 32) {
      std::memcpy(dst, src, dst_stride);
      for (LONG x = 0; x < dib.width; ++x) {
        if (dst[x * 4 + 3] != 0) {
          has_alpha = true;
        }
      }
    } else {
      for (LONG x = 0; x < dib.width; ++x) {
        dst[x * 4] = src[x * 3 + 2];
        dst[x * 4 + 1] = src[x * 3 + 1];
        dst[x * 4 + 2] = src[x * 3];
        dst[x * 4 + 3] = 255;
      }
    }
  }
  if (dib.bit_count == 32 && !has_alpha) {
    for (size_t i = 3; i < bgra->size(); i += 4) {
      (*bgra)[i] = 255;
    }
  }
  return true;
}

// Encodes BGRA pixels to a PNG file via WIC.
bool WriteBgraAsPng(const std::vector<uint8_t>& bgra, LONG width, LONG height,
                    const std::wstring& path) {
  ComScope com;
  Microsoft::WRL::ComPtr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&factory)))) {
    return false;
  }
  Microsoft::WRL::ComPtr<IWICStream> stream;
  if (FAILED(factory->CreateStream(&stream)) ||
      FAILED(stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE))) {
    return false;
  }
  Microsoft::WRL::ComPtr<IWICBitmapEncoder> encoder;
  if (FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder)) ||
      FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) {
    return false;
  }
  Microsoft::WRL::ComPtr<IWICBitmapFrameEncode> frame;
  Microsoft::WRL::ComPtr<IPropertyBag2> props;
  if (FAILED(encoder->CreateNewFrame(&frame, &props)) ||
      FAILED(frame->Initialize(props.Get()))) {
    return false;
  }
  frame->SetSize(static_cast<UINT>(width), static_cast<UINT>(height));
  WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
  if (FAILED(frame->SetPixelFormat(&format))) {
    return false;
  }
  const UINT stride = static_cast<UINT>(width) * 4;
  if (FAILED(frame->WritePixels(static_cast<UINT>(height), stride,
                                static_cast<UINT>(bgra.size()),
                                reinterpret_cast<BYTE*>(const_cast<uint8_t*>(bgra.data()))))) {
    return false;
  }
  return SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit());
}

// CF_DIBV5 / CF_DIB global memory -> PNG file.
bool WriteClipboardDibAsPng(HANDLE handle, const std::wstring& path, LONG* out_w, LONG* out_h) {
  const size_t size = GlobalSize(handle);
  auto* dib = GlobalLock(handle);
  if (!dib) {
    return false;
  }
  DibLayout layout;
  std::vector<uint8_t> bgra;
  const bool ok =
      ParseDibLayout(dib, size, &layout) && ExtractBgraFromDib(layout, &bgra) &&
      WriteBgraAsPng(bgra, layout.width, layout.height, path);
  GlobalUnlock(handle);
  if (ok) {
    *out_w = layout.width;
    *out_h = layout.height;
  }
  return ok;
}

// CF_BITMAP -> 32bpp top-down DIB -> PNG file.
bool WriteClipboardBitmapAsPng(HANDLE handle, const std::wstring& path, LONG* out_w, LONG* out_h) {
  auto* bitmap = static_cast<HBITMAP>(handle);
  BITMAP info = {};
  if (GetObjectW(bitmap, sizeof(info), &info) != sizeof(info) || info.bmWidth <= 0 ||
      info.bmHeight <= 0) {
    return false;
  }
  BITMAPINFOHEADER header = {};
  header.biSize = sizeof(header);
  header.biWidth = info.bmWidth;
  header.biHeight = -info.bmHeight;  // top-down
  header.biPlanes = 1;
  header.biBitCount = 32;
  header.biCompression = BI_RGB;

  std::vector<uint8_t> bits(static_cast<size_t>(info.bmWidth) * info.bmHeight * 4);
  HDC dc = GetDC(nullptr);
  if (!dc) {
    return false;
  }
  const int lines = GetDIBits(dc, bitmap, 0, info.bmHeight, bits.data(),
                              reinterpret_cast<BITMAPINFO*>(&header), DIB_RGB_COLORS);
  ReleaseDC(nullptr, dc);
  if (lines != info.bmHeight) {
    return false;
  }
  if (!WriteBgraAsPng(bits, info.bmWidth, info.bmHeight, path)) {
    return false;
  }
  *out_w = info.bmWidth;
  *out_h = info.bmHeight;
  return true;
}

// Finds the first supported attachment file path inside a CF_HDROP; empty
// when none. Also reports the first file of any type via |first_any| (empty
// when the drop holds no files), so the caller can distinguish "no file"
// from "file of unsupported type". The Dart layer applies the final mime
// whitelist.
std::wstring FirstAttachmentFileFromDrop(HANDLE handle, std::wstring* first_any) {
  *first_any = L"";
  auto* drop = static_cast<HDROP>(GlobalLock(handle));
  if (!drop) {
    return L"";
  }
  const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  std::wstring found;
  for (UINT i = 0; i < count; ++i) {
    const UINT length = DragQueryFileW(drop, i, nullptr, 0);
    std::wstring path(length + 1, L'\0');
    DragQueryFileW(drop, i, path.data(), static_cast<UINT>(path.size()));
    path.resize(length);
    const bool supported = found.empty() && IsSupportedFileExtension(path);
    if (first_any->empty()) {
      *first_any = path;
    }
    if (supported) {
      found = std::move(path);
    }
  }
  GlobalUnlock(handle);
  return found;
}

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) {
    return {};
  }
  const int length = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                         static_cast<int>(wide.size()), nullptr, 0, nullptr,
                                         nullptr);
  if (length <= 0) {
    return {};
  }
  std::string utf8(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()), utf8.data(),
                      length, nullptr, nullptr);
  return utf8;
}

EncodableMap BitmapResult(const std::string& path, LONG width, LONG height) {
  EncodableMap map;
  map[EncodableValue("kind")] = EncodableValue("bitmap");
  map[EncodableValue("path")] = EncodableValue(path);
  map[EncodableValue("width")] = EncodableValue(static_cast<int>(width));
  map[EncodableValue("height")] = EncodableValue(static_cast<int>(height));
  return map;
}

// Reads an image from the clipboard. Returns an empty map (serialized as null)
// when no image is present.
EncodableMap ReadClipboardImage() {
  EncodableMap result;
  // A clipboard held by another process is treated as "no image"; the caller
  // falls back to text paste.
  if (!OpenClipboard(nullptr)) {
    return result;
  }

  // Remembers the first dropped file when it has an unsupported type, so a
  // hint can be reported when nothing pasteable is found.
  std::wstring unsupported_file;
  if (IsClipboardFormatAvailable(CF_HDROP)) {
    if (HANDLE handle = GetClipboardData(CF_HDROP)) {
      std::wstring first_any;
      const std::wstring path = FirstAttachmentFileFromDrop(handle, &first_any);
      const std::string utf8 = WideToUtf8(path);
      if (!utf8.empty()) {
        result[EncodableValue("kind")] = EncodableValue("file");
        result[EncodableValue("path")] = EncodableValue(utf8);
      } else {
        unsupported_file = first_any;
      }
    }
  }

  if (result.empty()) {
    LONG width = 0;
    LONG height = 0;
    const UINT dib_formats[] = {CF_DIBV5, CF_DIB};
    for (UINT format : dib_formats) {
      HANDLE handle = IsClipboardFormatAvailable(format) ? GetClipboardData(format) : nullptr;
      if (!handle) {
        continue;
      }
      const std::wstring path = MakeTempPngPath();
      if (path.empty()) {
        break;
      }
      if (WriteClipboardDibAsPng(handle, path, &width, &height)) {
        result = BitmapResult(WideToUtf8(path), width, height);
        break;
      }
    }
  }

  if (result.empty() && IsClipboardFormatAvailable(CF_BITMAP)) {
    if (HANDLE handle = GetClipboardData(CF_BITMAP)) {
      const std::wstring path = MakeTempPngPath();
      LONG width = 0;
      LONG height = 0;
      if (!path.empty() && WriteClipboardBitmapAsPng(handle, path, &width, &height)) {
        result = BitmapResult(WideToUtf8(path), width, height);
      }
    }
  }

  // Report an unsupported dropped file only when nothing pasteable (supported
  // file or bitmap) was found; the caller shows a hint and still falls back
  // to text paste.
  if (result.empty() && !unsupported_file.empty()) {
    const std::string utf8 = WideToUtf8(unsupported_file);
    if (!utf8.empty()) {
      result[EncodableValue("kind")] = EncodableValue("file-unsupported");
      result[EncodableValue("path")] = EncodableValue(utf8);
    }
  }

  CloseClipboard();
  return result;
}

// Registered once per window engine; the channel must stay alive to receive
// method calls. Held for the process lifetime, matching the other channels in
// flutter_window.cpp.
std::vector<std::unique_ptr<Channel>>& Channels() {
  static std::vector<std::unique_ptr<Channel>> channels;
  return channels;
}

}  // namespace

void RegisterClipboardImageChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<Channel>(messenger, kChannelName,
                                           &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() != kReadImageMethod) {
          result->NotImplemented();
          return;
        }
        EncodableMap map = ReadClipboardImage();
        if (map.empty()) {
          result->Success(EncodableValue());
        } else {
          result->Success(EncodableValue(map));
        }
      });
  Channels().emplace_back(std::move(channel));
}

}  // namespace clipboard_image
