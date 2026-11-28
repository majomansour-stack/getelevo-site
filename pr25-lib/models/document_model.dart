class Document {
  final String id;
  final String unitId;
  final String propertyId;
  final String landlordId;
  final String uploadedBy;
  final String fileUrl;
  final String fileName;
  final int fileSize;
  final String docType;
  final String? signatureStatus;
  final DateTime createdAt;

  const Document({
    required this.id,
    required this.unitId,
    required this.propertyId,
    required this.landlordId,
    required this.uploadedBy,
    required this.fileUrl,
    required this.fileName,
    this.fileSize = 0,
    required this.docType,
    this.signatureStatus,
    required this.createdAt,
  });

  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1048576) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / 1048576).toStringAsFixed(1)} MB';
  }

  static const docTypes = ['Lease', 'Checklist', 'Inspection', 'Notice', 'Receipt', 'Other'];
}
