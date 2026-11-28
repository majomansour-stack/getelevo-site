import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> savePdfFile(Uint8List bytes, String filename) async {
  // Convert bytes to a JS Uint8Array then wrap in a Blob
  final jsArray = bytes.toJS;
  final blobParts = [jsArray].toJS;
  final options = web.BlobPropertyBag(type: 'application/pdf');
  final blob = web.Blob(blobParts, options);

  // Create a temporary object URL and trigger click-to-download
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
