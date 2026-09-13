/// Attachment rules and display helpers, mirroring `ALLOWED_ATTACHMENT_TYPES`
/// in the backend's `app/schemas/note.py`.
///
/// The type comes from the extension, not from the picker: Android reports no
/// MIME type for many documents, and the PUT header must match exactly what
/// the URL was presigned for.
library;

import 'package:flutter/material.dart';

const maxAttachmentBytes = 100 * 1024 * 1024;

const _typesByExtension = <String, String>{
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'odt': 'application/vnd.oasis.opendocument.text',
  'odp': 'application/vnd.oasis.opendocument.presentation',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'zip': 'application/zip',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'mp4': 'video/mp4',
  'webm': 'video/webm',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'flac': 'audio/flac',
};

/// For the file picker's `allowedExtensions`.
final attachmentExtensions = _typesByExtension.keys.toList(growable: false);

/// The content type to presign with, or null when the file is not allowed.
String? attachmentContentType(String filename) {
  if (!filename.contains('.')) return null;
  return _typesByExtension[filename.split('.').last.toLowerCase()];
}

String formatBytes(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData fileIcon(String contentType) {
  if (contentType == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (contentType.startsWith('image/')) return Icons.image_outlined;
  if (contentType.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (contentType.startsWith('video/')) return Icons.movie_outlined;
  if (contentType.contains('presentation') ||
      contentType.contains('powerpoint')) {
    return Icons.slideshow_outlined;
  }
  if (contentType.contains('spreadsheet') ||
      contentType.contains('excel') ||
      contentType == 'text/csv') {
    return Icons.table_chart_outlined;
  }
  if (contentType.contains('zip')) return Icons.folder_zip_outlined;
  if (contentType.contains('word') || contentType.startsWith('text/')) {
    return Icons.description_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "20 Sep 2026, 23:59" in the device's timezone.
///
/// The API sends instants; `DateTime.parse` keeps them in UTC. Formatting
/// without `.toLocal()` would show a Kathmandu student a deadline five hours
/// and forty-five minutes early — which is why this takes care of it rather
/// than trusting every call site to remember.
String formatLocalDateTime(DateTime instant, {bool withTime = true}) {
  final local = instant.toLocal();
  final date = '${local.day} ${_months[local.month - 1]} ${local.year}';
  if (!withTime) return date;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$date, $hh:$mm';
}

/// Keep only characters that are safe in a filename on every platform.
String safeFilename(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  return cleaned.isEmpty ? 'download' : cleaned;
}
