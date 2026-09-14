#ifndef RUNNER_CLIPBOARD_IMAGE_CHANNEL_H_
#define RUNNER_CLIPBOARD_IMAGE_CHANNEL_H_

#include <flutter/binary_messenger.h>

namespace clipboard_image {

// Registers the "orbby_clipboard_image" channel for reading images from the
// clipboard. Methods:
//   readImage -> null when no image; {kind:"file", path} for an image file;
//   bitmap data (screenshots) is encoded to a PNG temp file and returned as
//   {kind:"bitmap", path, width, height}.
// Supported formats: CF_HDROP (image file), CF_DIBV5 / CF_DIB / CF_BITMAP
// (24/32bpp). Each window engine must register once (multi-window).
void RegisterClipboardImageChannel(flutter::BinaryMessenger* messenger);

}  // namespace clipboard_image

#endif  // RUNNER_CLIPBOARD_IMAGE_CHANNEL_H_
