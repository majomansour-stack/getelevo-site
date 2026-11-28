/// Cross-platform PDF download helper.
/// On web: triggers a native browser "Save As" download via JS blob URL — no plugin needed.
/// On mobile: uses Printing.sharePdf (native share / save sheet).
import 'dart:typed_data';

import 'pdf_saver_io.dart'
    if (dart.library.js_interop) 'pdf_saver_web.dart' as impl;

Future<void> savePdfFile(Uint8List bytes, String filename) =>
    impl.savePdfFile(bytes, filename);
