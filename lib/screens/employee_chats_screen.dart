import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/notification_service.dart';
import '../services/translations.dart';

class EmployeeChatsScreen extends StatefulWidget {
  final int clientId;
  final int employeeId;
  final String employeeName;

  const EmployeeChatsScreen({
    super.key,
    required this.clientId,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<EmployeeChatsScreen> createState() => _EmployeeChatsScreenState();
}

class _EmployeeChatsScreenState extends State<EmployeeChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatConversationSummary> _conversations = [];
  bool _isLoading = true;
  String? _error;
  Timer? _pollTimer;
  int _lastUnreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final conversations = await ApiService.getChatConversations(
        widget.clientId,
        widget.employeeId,
      );

      final unreadCount =
          conversations.fold<int>(0, (sum, item) => sum + item.unreadCount);
      if (silent &&
          mounted &&
          unreadCount > _lastUnreadCount &&
          conversations.any((item) => item.unreadCount > 0)) {
        final latestUnread =
            conversations.firstWhere((item) => item.unreadCount > 0);
        await NotificationService().showChatMessageNotification(
          title: latestUnread.title,
          message: latestUnread.lastMessage.isEmpty
              ? Translations.getText(
                  'chat_new_message_arrived',
                  context.read<LanguageService>().currentLocale.languageCode,
                )
              : latestUnread.lastMessage,
        );
      }

      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _isLoading = false;
        _error = null;
        _lastUnreadCount = unreadCount;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _loadConversations(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final languageService = context.watch<LanguageService>();
    final lang = languageService.currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;
    final term = _searchController.text.trim().toLowerCase();
    final filtered = _conversations.where((item) {
      if (term.isEmpty) return true;
      return item.title.toLowerCase().contains(term) ||
          item.lastMessage.toLowerCase().contains(term);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.getText('employee_chats', lang)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: Translations.getText('search_chats', lang),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorState(lang, scheme)
                    : filtered.isEmpty
                        ? _buildEmptyState(lang, scheme)
                        : RefreshIndicator(
                            onRefresh: _loadConversations,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                return _ConversationTile(
                                  item: item,
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChatConversationScreen(
                                          clientId: widget.clientId,
                                          employeeId: widget.employeeId,
                                          employeeName: widget.employeeName,
                                          conversationId: item.conversationId,
                                          initialTitle: item.title,
                                        ),
                                      ),
                                    );
                                    await _loadConversations(silent: true);
                                  },
                                );
                              },
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemCount: filtered.length,
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String lang, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              Translations.getText('chat_empty_title', lang),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              Translations.getText('chat_empty_desc', lang),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String lang, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              Translations.getText('chat_load_error', lang),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadConversations,
              child: Text(Translations.getText('retry', lang)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ChatConversationSummary item;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lang =
        Provider.of<LanguageService>(context).currentLocale.languageCode;
    final isUnread = item.unreadCount > 0;
    return Material(
      color: isUnread
            ? scheme.primaryContainer.withValues(alpha: 0.35)
          : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor:
                    item.isGroup ? scheme.secondaryContainer : scheme.primary,
                foregroundColor:
                    item.isGroup ? scheme.onSecondaryContainer : scheme.onPrimary,
                child: Icon(
                  item.isGroup ? Icons.groups_rounded : Icons.support_agent_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (item.unreadCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: scheme.error,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              item.unreadCount > 99
                                  ? '99+'
                                  : item.unreadCount.toString(),
                              style: TextStyle(
                                color: scheme.onError,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.lastMessage.isEmpty ? '...' : item.lastMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          item.isGroup ? Icons.groups_2_outlined : Icons.person_outline,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item.memberCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _friendlyTime(item.lastMessageAt, lang),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatConversationScreen extends StatefulWidget {
  final int clientId;
  final int employeeId;
  final int conversationId;
  final String employeeName;
  final String initialTitle;

  const ChatConversationScreen({
    super.key,
    required this.clientId,
    required this.employeeId,
    required this.employeeName,
    required this.conversationId,
    required this.initialTitle,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  ChatConversationInfo? _conversation;
  List<ChatMessageModel> _messages = [];
  List<PlatformFile> _selectedAttachments = [];
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages(initial: true);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool initial = false}) async {
    if (initial && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final payload = await ApiService.getChatMessages(
        widget.clientId,
        widget.employeeId,
        widget.conversationId,
      );
      await ApiService.markChatConversationRead(
        widget.clientId,
        widget.employeeId,
        widget.conversationId,
      );

      if (!mounted) return;
      setState(() {
        _conversation = payload.conversation;
        _messages = payload.messages;
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (_) {
      if (!mounted) return;
      if (initial) {
        setState(() => _isLoading = false);
        final lang = context.read<LanguageService>().currentLocale.languageCode;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Translations.getText('chat_load_error', lang)),
          ),
        );
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadMessages();
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if ((message.isEmpty && _selectedAttachments.isEmpty) || _isSending) return;

    setState(() => _isSending = true);
    bool ok = false;
    String? errorMessage;
    try {
      if (_selectedAttachments.isNotEmpty) {
        final attachments = await _buildAttachmentPayloads(_selectedAttachments);
        if (attachments.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر قراءة الملف المختار من الجهاز. جرّب اختيار الملف مرة أخرى.'),
            ),
          );
          setState(() => _isSending = false);
          return;
        }

        final result = await ApiService.sendChatAttachments(
          widget.clientId,
          widget.employeeId,
          widget.conversationId,
          message: message,
          attachments: attachments,
        );
        ok = result.success;
        errorMessage = result.message;
      } else {
        ok = await ApiService.sendChatMessage(
          widget.clientId,
          widget.employeeId,
          widget.conversationId,
          message,
        );
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;

    if (ok) {
      _messageController.clear();
      setState(() => _selectedAttachments = []);
      await _loadMessages();
      _focusNode.requestFocus();
    } else {
      final lang = context.read<LanguageService>().currentLocale.languageCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage?.trim().isNotEmpty == true
              ? errorMessage!
              : Translations.getText('chat_send_error', lang)),
        ),
      );
    }

    if (mounted) {
      setState(() => _isSending = false);
    }
  }

  Future<void> _pickAttachments() async {
    if (_isSending) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) return;

    final oversized = result.files.where((file) => file.size > 15 * 1024 * 1024);
    if (oversized.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أحد الملفات المختارة يتجاوز الحد المسموح 15MB'),
        ),
      );
      return;
    }

    setState(() {
      _selectedAttachments = [..._selectedAttachments, ...result.files];
    });
  }

  void _removeAttachmentAt(int index) {
    if (index < 0 || index >= _selectedAttachments.length) return;
    setState(() {
      _selectedAttachments =
          List<PlatformFile>.from(_selectedAttachments)..removeAt(index);
    });
  }

  Future<List<({String fileName, List<int> bytes, String? contentType})>>
      _buildAttachmentPayloads(List<PlatformFile> files) async {
    final result =
        <({String fileName, List<int> bytes, String? contentType})>[];

    for (final file in files) {
      // #region debug-point A:attachment-payload-source
      unawaited(ApiService.reportChatImageDebug(
        'A',
        'employee_chats_screen.dart:_buildAttachmentPayloads:start',
        'Preparing attachment payload from picker result',
        data: {
          'fileName': file.name,
          'size': file.size,
          'extension': file.extension,
          'hasBytes': file.bytes != null,
          'path': file.path,
        },
      ));
      // #endregion
      List<int>? bytes = file.bytes?.toList();

      if ((bytes == null || bytes.isEmpty) &&
          file.path != null &&
          file.path!.trim().isNotEmpty) {
        try {
          bytes = await File(file.path!).readAsBytes();
        } catch (_) {
          bytes = null;
        }
      }

      if (bytes == null || bytes.isEmpty) {
        // #region debug-point A:attachment-payload-empty
        unawaited(ApiService.reportChatImageDebug(
          'A',
          'employee_chats_screen.dart:_buildAttachmentPayloads:empty',
          'Attachment payload bytes are empty after read attempt',
          data: {
            'fileName': file.name,
            'size': file.size,
            'extension': file.extension,
            'path': file.path,
          },
        ));
        // #endregion
        continue;
      }

      // #region debug-point A:attachment-payload-ready
      unawaited(ApiService.reportChatImageDebug(
        'A',
        'employee_chats_screen.dart:_buildAttachmentPayloads:ready',
        'Attachment payload bytes ready',
        data: {
          'fileName': file.name,
          'size': file.size,
          'preparedBytes': bytes.length,
          'contentType': file.extension != null && file.extension!.isNotEmpty
              ? _contentTypeFromExtension(file.extension!)
              : null,
        },
      ));
      // #endregion
      result.add((
        fileName: file.name,
        bytes: bytes,
        contentType:
            file.extension != null && file.extension!.isNotEmpty
                ? _contentTypeFromExtension(file.extension!)
                : null,
      ));
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final languageService = context.watch<LanguageService>();
    final lang = languageService.currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_conversation?.title ?? widget.initialTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _conversation == null
                  ? ''
                  : _conversation!.isGroup
                      ? '${Translations.getText('chat_group_label', lang)} - ${_conversation!.memberCount} ${Translations.getText('chat_members', lang)}'
                      : Translations.getText('chat_direct_label', lang),
              style: TextStyle(
                color: scheme.onPrimary.withValues(alpha: 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Text(
                            Translations.getText('chat_no_messages', lang),
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final item = _messages[index];
                            return _MessageBubble(
                              message: item,
                              clientId: widget.clientId,
                              employeeId: widget.employeeId,
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedAttachments.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(
                                _selectedAttachments.length,
                                (index) {
                                  final file = _selectedAttachments[index];
                                  return Chip(
                                    avatar: const Icon(Icons.attach_file_rounded,
                                        size: 18),
                                    label: Text(
                                      '${file.name} (${_formatFileSize(file.size)})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onDeleted: _isSending
                                        ? null
                                        : () => _removeAttachmentAt(index),
                                  );
                                },
                              ),
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton.filledTonal(
                              onPressed: _isSending ? null : _pickAttachments,
                              icon: const Icon(Icons.attach_file_rounded),
                              tooltip: 'إرفاق ملف',
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                focusNode: _focusNode,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.newline,
                                onSubmitted: (_) => _sendMessage(),
                                decoration: InputDecoration(
                                  hintText: Translations.getText(
                                      'chat_input_placeholder', lang),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: _isSending ? null : _sendMessage,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(56, 56),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: _isSending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final int clientId;
  final int employeeId;

  const _MessageBubble({
    required this.message,
    required this.clientId,
    required this.employeeId,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lang =
        Provider.of<LanguageService>(context).currentLocale.languageCode;
    final alignment =
        message.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor =
        message.isMine ? scheme.primary : scheme.surfaceContainerHighest;
    final textColor = message.isMine ? scheme.onPrimary : scheme.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(message.isMine ? 18 : 6),
      bottomRight: Radius.circular(message.isMine ? 6 : 18),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          if (!message.isMine && message.senderName.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 8, right: 8),
              child: Text(
                message.senderName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: radius,
            ),
            child: Column(
              crossAxisAlignment: alignment,
              children: [
                if (message.messageText.trim().isNotEmpty)
                  Text(
                    message.messageText,
                    style: TextStyle(color: textColor, height: 1.45),
                  ),
                if (message.attachments.isNotEmpty) ...[
                  SizedBox(height: message.messageText.trim().isNotEmpty ? 8 : 0),
                  ...message.attachments.map(
                    (attachment) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _MessageAttachmentTile(
                        attachment: attachment,
                        employeeId: employeeId,
                        clientId: clientId,
                        isMine: message.isMine,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _friendlyTime(message.createdAt, lang),
                      style: TextStyle(
                        fontSize: 11,
                        color: message.isMine
                            ? scheme.onPrimary.withValues(alpha: 0.85)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (message.isMine) ...[
                      const SizedBox(width: 6),
                      Icon(
                        message.readByAllRecipients
                            ? Icons.done_all_rounded
                            : Icons.done_rounded,
                        size: 16,
                        color: message.readByAllRecipients
                            ? Colors.lightBlueAccent
                            : scheme.onPrimary.withValues(alpha: 0.8),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageAttachmentTile extends StatelessWidget {
  final ChatAttachmentModel attachment;
  final int clientId;
  final int employeeId;
  final bool isMine;

  const _MessageAttachmentTile({
    required this.attachment,
    required this.clientId,
    required this.employeeId,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attachmentUrl = ApiService.getChatAttachmentUrl(
      clientId,
      employeeId,
      attachment.attachmentId,
    );

    if (_isImageAttachment(attachment)) {
      return _MessageImageAttachment(
        attachment: attachment,
        imageUrl: attachmentUrl,
        isMine: isMine,
      );
    }

    final bgColor = isMine
        ? Colors.white.withValues(alpha: 0.12)
        : scheme.surfaceContainerHighest;
    final fgColor = isMine ? Colors.white : scheme.onSurface;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final uri = Uri.parse(attachmentUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file_rounded, size: 18, color: fgColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${attachment.fileName} (${_formatFileSize(attachment.fileSize)})',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fgColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageImageAttachment extends StatelessWidget {
  final ChatAttachmentModel attachment;
  final String imageUrl;
  final bool isMine;

  const _MessageImageAttachment({
    required this.attachment,
    required this.imageUrl,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    double previewWidth = MediaQuery.sizeOf(context).width * 0.58;
    if (previewWidth < 180) previewWidth = 180;
    if (previewWidth > 220) previewWidth = 220;
    final previewHeight = previewWidth * 1.08;
    final borderColor = isMine
        ? Colors.white.withValues(alpha: 0.18)
        : Theme.of(context).colorScheme.outlineVariant;

    return GestureDetector(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('تعذر تحميل الصورة'),
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        width: previewWidth,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: previewHeight,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    alignment: Alignment.center,
                    color: Colors.black12,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  alignment: Alignment.center,
                  color: Colors.black12,
                  padding: const EdgeInsets.all(12),
                  child: Builder(
                    builder: (context) {
                      // #region debug-point E:image-render-failed
                      unawaited(ApiService.reportChatImageDebug(
                        'E',
                        'employee_chats_screen.dart:_MessageImageAttachment:errorBuilder',
                        'Image.network failed to render chat attachment',
                        data: {
                          'attachmentId': attachment.attachmentId,
                          'fileName': attachment.fileName,
                          'contentType': attachment.contentType,
                          'imageUrl': imageUrl,
                        },
                      ));
                      // #endregion
                      return const Text(
                        'تعذر تحميل الصورة',
                        textAlign: TextAlign.center,
                      );
                    },
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: Colors.black.withValues(alpha: isMine ? 0.14 : 0.04),
              child: Text(
                attachment.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isMine ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _friendlyTime(String? value, String lang) {
  if (value == null || value.trim().isEmpty) return '';
  final date = DateTime.tryParse(value.replaceFirst(' ', 'T'));
  if (date == null) return value;
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes < 1) {
    return Translations.getText('chat_time_now', lang);
  }
  if (diff.inHours < 1) {
    return Translations.getTextWithParams(
      'chat_time_minutes_ago',
      lang,
      {'count': diff.inMinutes.toString()},
    );
  }
  if (diff.inDays < 1) {
    return Translations.getTextWithParams(
      'chat_time_hours_ago',
      lang,
      {'count': diff.inHours.toString()},
    );
  }
  return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
}

String _formatFileSize(int size) {
  if (size >= 1024 * 1024) {
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (size >= 1024) {
    return '${(size / 1024).round()} KB';
  }
  return '$size B';
}

bool _isImageAttachment(ChatAttachmentModel attachment) {
  if (attachment.contentType.toLowerCase().startsWith('image/')) {
    return true;
  }

  final name = attachment.fileName.toLowerCase();
  return name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.png') ||
      name.endsWith('.gif') ||
      name.endsWith('.webp') ||
      name.endsWith('.bmp');
}

String? _contentTypeFromExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'txt':
      return 'text/plain';
    default:
      return null;
  }
}
