import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Triggers a browser "Save file" dialog for any file type.
void downloadFileOnWeb(Uint8List bytes, String filename) {
  final jsArray = bytes.toJS;
  final blobParts = [jsArray].toJS;

  // Determine MIME type from extension
  final ext = filename.split('.').last.toLowerCase();
  final mime = switch (ext) {
    'pdf'  => 'application/pdf',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'doc'  => 'application/msword',
    'png'  => 'image/png',
    'jpg'  || 'jpeg' => 'image/jpeg',
    _      => 'application/octet-stream',
  };

  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mime));
  final url  = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href     = url
    ..download = filename;

  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
