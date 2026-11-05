// CityResolve photo media (P1): controlled local storage + reference.
//
// Principle: bytes NEVER travel through state.json or MongoDB
// documents. Only the `mediaId` identifier is persisted in
// `Report.photo`. Files live under `data/uploads/`.
import 'dart:io';
import 'dart:math';

/// Maximum accepted size: 5 MB (well below the API's 50 MB inline,
/// sandbox safeguard).
const int maxPhotoBytes = 5 * 1024 * 1024;

/// Permanent identifier: 24 hexadecimal characters (secure random).
String newMediaId() {
  final rng = Random.secure();
  final sb = StringBuffer();
  for (var i = 0; i < 24; i++) {
    sb.write(rng.nextInt(16).toRadixString(16));
  }
  return sb.toString();
}

bool isMediaId(String s) =>
    RegExp(r'^[0-9a-f]{24}$').hasMatch(s);

/// Type detection by magic bytes (never by the provided extension).
/// Returns the safe extension or null if the type is unknown/dangerous.
String? detectImageExt(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'jpg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E &&
      bytes[3] == 0x47 && bytes[4] == 0x0D && bytes[5] == 0x0A &&
      bytes[6] == 0x1A && bytes[7] == 0x0A) {
    return 'png';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) && bytes[5] == 0x61) {
    return 'gif';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 &&
      bytes[3] == 0x46 && bytes[8] == 0x57 && bytes[9] == 0x45 &&
      bytes[10] == 0x42 && bytes[11] == 0x50) {
    return 'webp';
  }
  return null;
}

String mimeForExt(String ext) => switch (ext) {
      'jpg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };

class MediaValidationError implements Exception {
  final String message;
  const MediaValidationError(this.message);
  @override
  String toString() => message;
}

/// Validates the received bytes. Throws MediaValidationError otherwise.
String validateImageBytes(List<int> bytes) {
  if (bytes.isEmpty) {
    throw const MediaValidationError('empty file: no bytes received');
  }
  if (bytes.length > maxPhotoBytes) {
    throw MediaValidationError(
        'file too large (${bytes.length} bytes, max $maxPhotoBytes)');
  }
  final ext = detectImageExt(bytes);
  if (ext == null) {
    throw const MediaValidationError(
        'unrecognized file type (jpeg/png/gif/webp expected, verified by magic bytes)');
  }
  return ext;
}

/// Safe path: fixed directory + validated mediaId + validated extension.
/// No client-provided name is ever used.
File mediaFile(String uploadsDir, String mediaId, String ext) {
  if (!isMediaId(mediaId)) {
    throw const MediaValidationError('invalid media identifier');
  }
  if (!{'jpg', 'png', 'gif', 'webp'}.contains(ext)) {
    throw const MediaValidationError('extension not allowed');
  }
  return File('$uploadsDir/$mediaId.$ext');
}

File mediaMetaFile(String uploadsDir, String mediaId) {
  if (!isMediaId(mediaId)) {
    throw const MediaValidationError('invalid media identifier');
  }
  return File('$uploadsDir/$mediaId.json');
}

/// Validates the visual analysis output contract (§7: example contract,
/// never ground truth). Returns null if valid, otherwise the reason.
String? validateVisualAnalysis(Map<String, dynamic> out) {
  if (out['observationsVisibles'] is! List ||
      (out['observationsVisibles'] as List).isEmpty) {
    return 'observationsVisibles missing or empty';
  }
  if (out['problemesPossibles'] is! List) {
    return 'problemesPossibles missing';
  }
  for (final p in (out['problemesPossibles'] as List)) {
    if (p is! Map ||
        p['famille'] is! String ||
        p['hypothese'] is! String ||
        p['confirmation'] is! String) {
      return 'problemePossible malformed (famille/hypothese/confirmation required)';
    }
  }
  if (out['incertitudes'] is! List ||
      (out['incertitudes'] as List).isEmpty) {
    return 'incertitudes missing (an analysis without uncertainty is refused)';
  }
  return null;
}
