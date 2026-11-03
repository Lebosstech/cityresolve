// Médias photos CityResolve (P1) : stockage local contrôlé + référence.
//
// Principe : les octets ne transitent JAMAIS dans state.json ni dans les
// documents MongoDB. Seul l'identifiant `mediaId` est persisté dans
// `Report.photo`. Les fichiers vivent sous `data/uploads/`.
import 'dart:io';
import 'dart:math';

/// Taille maximale acceptée : 5 Mo (bien en dessous des 50 Mo inline de
/// l'API, garde-fou de bac à sable).
const int maxPhotoBytes = 5 * 1024 * 1024;

/// Identifiant permanent : 24 caractères hexadécimaux (aléatoire sûr).
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

/// Détection du type par octets magiques (jamais par l'extension fournie).
/// Retourne l'extension sûre ou null si type inconnu/dangereux.
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

/// Valide les octets reçus. Lève MediaValidationError sinon.
String validateImageBytes(List<int> bytes) {
  if (bytes.isEmpty) {
    throw const MediaValidationError('fichier vide : aucun octet reçu');
  }
  if (bytes.length > maxPhotoBytes) {
    throw MediaValidationError(
        'fichier trop volumineux (${bytes.length} octets, max $maxPhotoBytes)');
  }
  final ext = detectImageExt(bytes);
  if (ext == null) {
    throw const MediaValidationError(
        'type de fichier non reconnu (jpeg/png/gif/webp attendus, vérifiés par octets magiques)');
  }
  return ext;
}

/// Chemin sûr : répertoire fixe + mediaId validé + extension validée.
/// Aucun nom fourni par le client n'est jamais utilisé.
File mediaFile(String uploadsDir, String mediaId, String ext) {
  if (!isMediaId(mediaId)) {
    throw const MediaValidationError('identifiant média invalide');
  }
  if (!{'jpg', 'png', 'gif', 'webp'}.contains(ext)) {
    throw const MediaValidationError('extension non autorisée');
  }
  return File('$uploadsDir/$mediaId.$ext');
}

File mediaMetaFile(String uploadsDir, String mediaId) {
  if (!isMediaId(mediaId)) {
    throw const MediaValidationError('identifiant média invalide');
  }
  return File('$uploadsDir/$mediaId.json');
}

/// Valide le contrat de sortie d'analyse visuelle (§7 : exemple de contrat,
/// jamais une vérité terrain). Retourne null si valide, sinon le motif.
String? validateVisualAnalysis(Map<String, dynamic> out) {
  if (out['observationsVisibles'] is! List ||
      (out['observationsVisibles'] as List).isEmpty) {
    return 'observationsVisibles absent ou vide';
  }
  if (out['problemesPossibles'] is! List) {
    return 'problemesPossibles absent';
  }
  for (final p in (out['problemesPossibles'] as List)) {
    if (p is! Map ||
        p['famille'] is! String ||
        p['hypothese'] is! String ||
        p['confirmation'] is! String) {
      return 'problemePossible mal formé (famille/hypothese/confirmation requis)';
    }
  }
  if (out['incertitudes'] is! List ||
      (out['incertitudes'] as List).isEmpty) {
    return 'incertitudes absentes (une analyse sans incertitude est refusée)';
  }
  return null;
}
