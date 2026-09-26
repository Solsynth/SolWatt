import 'package:solar_network_sdk/solar_network_sdk.dart';

/// MIME types for the extensions the app renders itself.
///
/// A file's declared type is usually right, but attachments are the case where
/// it is not: mail parts arrive with no `Content-Type` at all or as
/// `application/octet-stream`, while the filename says exactly what the bytes
/// are. Anything not listed here keeps its declared type untouched.
const mimeTypeByExtension = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'avif': 'image/avif',
  'mp4': 'video/mp4',
  'm4v': 'video/x-m4v',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'avi': 'video/x-msvideo',
  '3gp': 'video/3gpp',
  'mpeg': 'video/mpeg',
  'mpg': 'video/mpeg',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
};

/// MIME types that carry no information about the bytes: whatever the filename
/// suggests is a better answer than "binary blob".
const _genericTypes = {
  '',
  'application/octet-stream',
  'binary/octet-stream',
};

/// The MIME type [name]'s extension implies, or null when it is not one of the
/// types this app knows.
String? mimeTypeForFilename(String name) {
  final dot = name.lastIndexOf('.');
  if (dot == -1 || dot == name.length - 1) return null;
  return mimeTypeByExtension[name.substring(dot + 1).toLowerCase()];
}

/// The MIME type to treat a file as: its declared type unless that says
/// nothing (`application/octet-stream`, empty) or contradicts a binary
/// extension — a `text/plain` part named `photo.jpg` is a mislabelled picture,
/// not a text file.
String effectiveMimeType({required String mimeType, required String name}) {
  final declared = mimeType.trim().toLowerCase();
  final implied = mimeTypeForFilename(name);
  if (implied == null) return declared;
  if (_genericTypes.contains(declared)) return implied;
  if (declared.startsWith('text/') && !implied.startsWith('text/')) {
    return implied;
  }
  return declared;
}

/// Whether [file] is a picture, judged by its MIME type or, when that is
/// missing or generic, by its filename.
bool isImageFile(IDisplayableCloudFile file) =>
    effectiveMimeType(mimeType: file.mimeType, name: file.name).startsWith(
      'image/',
    );

/// Whether [file] is a video, judged the same way as [isImageFile].
bool isVideoFile(IDisplayableCloudFile file) =>
    effectiveMimeType(mimeType: file.mimeType, name: file.name).startsWith(
      'video/',
    );
