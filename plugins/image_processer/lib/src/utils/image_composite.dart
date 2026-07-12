import 'package:image/image.dart' as img;

/// Composite an image with alpha onto a white background.
img.Image compositeOntoWhite(img.Image image) {
  return compositeOntoColor(image, img.ColorUint8.rgba(255, 255, 255, 255));
}

/// Composite an image with alpha onto a solid color background.
img.Image compositeOntoColor(img.Image image, img.Color bgColor) {
  final flat = img.Image(width: image.width, height: image.height);
  flat.clear(bgColor);
  img.compositeImage(flat, image);
  return flat;
}
