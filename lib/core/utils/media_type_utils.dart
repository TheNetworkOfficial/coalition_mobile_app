import 'package:mime/mime.dart';

/// Returns true when [source] appears to point to an image resource.
bool isLikelyImageSource(String? source) {
  if (source == null || source.isEmpty) {
    return false;
  }

  final normalized = _normalizeSourcePath(source);
  final mimeType = lookupMimeType(normalized);
  if (mimeType != null && mimeType.startsWith('image/')) {
    return true;
  }

  final lower = normalized.toLowerCase();
  return _imageExtensions.any(lower.endsWith);
}

String _normalizeSourcePath(String source) {
  final uri = Uri.tryParse(source);
  if (uri == null) {
    return source;
  }
  if (uri.scheme == 'file') {
    return uri.toFilePath();
  }
  if (uri.hasScheme) {
    return uri.path;
  }
  return uri.toString();
}

const Set<String> _imageExtensions = <String>{
  '.apng',
  '.avif',
  '.bmp',
  '.gif',
  '.heic',
  '.heif',
  '.ico',
  '.jpeg',
  '.jpg',
  '.png',
  '.svg',
  '.tif',
  '.tiff',
  '.webp',
};
