class ChatConversationSummary {
  final int conversationId;
  final String conversationType;
  final String title;
  final String lastMessage;
  final String? lastMessageAt;
  final int unreadCount;
  final int memberCount;

  const ChatConversationSummary({
    required this.conversationId,
    required this.conversationType,
    required this.title,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.memberCount,
  });

  bool get isGroup => conversationType.toLowerCase() == 'group';

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) =>
        value is int ? value : int.tryParse('${value ?? 0}') ?? 0;

    return ChatConversationSummary(
      conversationId: parseInt(json['ConversationID'] ?? json['conversationId']),
      conversationType:
          '${json['ConversationType'] ?? json['conversationType'] ?? 'direct'}',
      title: '${json['Title'] ?? json['title'] ?? ''}',
      lastMessage: '${json['LastMessage'] ?? json['lastMessage'] ?? ''}',
      lastMessageAt:
          (json['LastMessageAt'] ?? json['lastMessageAt'])?.toString(),
      unreadCount: parseInt(json['UnreadCount'] ?? json['unreadCount']),
      memberCount: parseInt(json['MemberCount'] ?? json['memberCount']),
    );
  }
}

class ChatConversationInfo {
  final int conversationId;
  final String conversationType;
  final String title;
  final int memberCount;

  const ChatConversationInfo({
    required this.conversationId,
    required this.conversationType,
    required this.title,
    required this.memberCount,
  });

  bool get isGroup => conversationType.toLowerCase() == 'group';

  factory ChatConversationInfo.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) =>
        value is int ? value : int.tryParse('${value ?? 0}') ?? 0;

    return ChatConversationInfo(
      conversationId: parseInt(json['ConversationID'] ?? json['conversationId']),
      conversationType:
          '${json['ConversationType'] ?? json['conversationType'] ?? 'direct'}',
      title: '${json['Title'] ?? json['title'] ?? ''}',
      memberCount: parseInt(json['MemberCount'] ?? json['memberCount']),
    );
  }
}

class ChatMessageModel {
  final int messageId;
  final int conversationId;
  final String senderType;
  final String senderName;
  final String messageText;
  final String createdAt;
  final bool isMine;
  final bool readByAllRecipients;
  final int readCount;
  final int recipientCount;
  final List<ChatAttachmentModel> attachments;

  const ChatMessageModel({
    required this.messageId,
    required this.conversationId,
    required this.senderType,
    required this.senderName,
    required this.messageText,
    required this.createdAt,
    required this.isMine,
    required this.readByAllRecipients,
    required this.readCount,
    required this.recipientCount,
    required this.attachments,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) =>
        value is int ? value : int.tryParse('${value ?? 0}') ?? 0;
    bool parseBool(dynamic value) {
      if (value is bool) return value;
      final normalized = '${value ?? ''}'.toLowerCase();
      return normalized == 'true' || normalized == '1';
    }

    return ChatMessageModel(
      messageId: parseInt(json['MessageID'] ?? json['messageId']),
      conversationId: parseInt(json['ConversationID'] ?? json['conversationId']),
      senderType: '${json['SenderType'] ?? json['senderType'] ?? ''}',
      senderName: '${json['SenderName'] ?? json['senderName'] ?? ''}',
      messageText: '${json['MessageText'] ?? json['messageText'] ?? ''}',
      createdAt: '${json['CreatedAt'] ?? json['createdAt'] ?? ''}',
      isMine: parseBool(json['IsMine'] ?? json['isMine']),
      readByAllRecipients:
          parseBool(json['ReadByAllRecipients'] ?? json['readByAllRecipients']),
      readCount: parseInt(json['ReadCount'] ?? json['readCount']),
      recipientCount: parseInt(json['RecipientCount'] ?? json['recipientCount']),
      attachments: ((json['Attachments'] ?? json['attachments']) as List? ?? [])
          .whereType<Map>()
          .map((item) => ChatAttachmentModel.fromJson(
              Map<String, dynamic>.from(item.cast<String, dynamic>())))
          .toList(),
    );
  }
}

class ChatAttachmentModel {
  final int attachmentId;
  final int messageId;
  final String fileName;
  final String contentType;
  final int fileSize;

  const ChatAttachmentModel({
    required this.attachmentId,
    required this.messageId,
    required this.fileName,
    required this.contentType,
    required this.fileSize,
  });

  factory ChatAttachmentModel.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) =>
        value is int ? value : int.tryParse('${value ?? 0}') ?? 0;

    return ChatAttachmentModel(
      attachmentId: parseInt(json['AttachmentID'] ?? json['attachmentId']),
      messageId: parseInt(json['MessageID'] ?? json['messageId']),
      fileName: '${json['FileName'] ?? json['fileName'] ?? 'attachment'}',
      contentType:
          '${json['ContentType'] ?? json['contentType'] ?? 'application/octet-stream'}',
      fileSize: parseInt(json['FileSize'] ?? json['fileSize']),
    );
  }
}
