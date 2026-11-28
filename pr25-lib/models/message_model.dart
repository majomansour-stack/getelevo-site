class Message {
  final String id;
  final String unitId;
  final String senderId;
  final String receiverId;
  final String messageText;
  final String? attachmentUrl;
  final String? attachmentType;
  final bool isRead;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.unitId,
    required this.senderId,
    required this.receiverId,
    required this.messageText,
    this.attachmentUrl,
    this.attachmentType,
    this.isRead = false,
    required this.createdAt,
  });
}

class Conversation {
  final String unitId;
  final String tenantId;
  final String tenantName;
  final String unitAddress;
  final Message? lastMessage;
  final int unreadCount;

  /// Set when this row is a repair job chat rather than the unit thread.
  final String? jobRequestId;
  final String jobStatus;

  const Conversation({
    required this.unitId,
    required this.tenantId,
    required this.tenantName,
    required this.unitAddress,
    this.lastMessage,
    this.unreadCount = 0,
    this.jobRequestId,
    this.jobStatus = '',
  });

  bool get isJobChat => jobRequestId != null && jobRequestId!.isNotEmpty;
}

/// A job chat the signed-in person belongs to.
class JobInboxThread {
  final String requestId;
  final String unitId;
  final String address;
  final String title;
  final String status;
  final String preview;
  final DateTime? at;

  const JobInboxThread({
    required this.requestId,
    required this.unitId,
    required this.address,
    required this.title,
    required this.status,
    required this.preview,
    this.at,
  });
}
