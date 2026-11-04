import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_vision/models/chat_models.dart';
import 'package:smart_vision/services/api_service.dart';
import 'package:smart_vision/services/language_service.dart';
import 'package:smart_vision/services/translations.dart';
import 'package:smart_vision/widgets/responsive_center.dart';

class ChatGroupInfoScreen extends StatefulWidget {
  final int clientId;
  final int employeeId;
  final int conversationId;
  final String groupTitle;
  final int memberCount;
  final List<ChatConversationMember> initialMembers;

  const ChatGroupInfoScreen({
    super.key,
    required this.clientId,
    required this.employeeId,
    required this.conversationId,
    required this.groupTitle,
    required this.memberCount,
    this.initialMembers = const [],
  });

  @override
  State<ChatGroupInfoScreen> createState() => _ChatGroupInfoScreenState();
}

class _ChatGroupInfoScreenState extends State<ChatGroupInfoScreen> {
  bool _isLoading = false;
  List<ChatConversationMember> _members = [];

  @override
  void initState() {
    super.initState();
    _members = widget.initialMembers;
    if (_members.isEmpty) {
      unawaited(_loadMembers());
    }
  }

  Future<void> _loadMembers() async {
    if (_isLoading) return;
    if (!mounted) return;
    setState(() => _isLoading = true);
    final members = await ApiService.getChatConversationMembers(
      widget.clientId,
      widget.employeeId,
      widget.conversationId,
    );
    if (!mounted) return;
    setState(() {
      _members = members;
      _isLoading = false;
    });
  }

  String _memberInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lang = context.watch<LanguageService>().currentLocale.languageCode;
    final countLabel =
        '${widget.memberCount} ${Translations.getText('chat_members', lang)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupTitle),
      ),
      body: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Card(
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.groupTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      countLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    Translations.getText('chat_members', lang),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _loadMembers,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: Translations.getText('reload', lang),
                )
              ],
            ),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: _isLoading && _members.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      children: List.generate(_members.length, (index) {
                        final member = _members[index];
                        final showDivider = index != _members.length - 1;
                        return Column(
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: scheme.primaryContainer,
                                foregroundColor: scheme.onPrimaryContainer,
                                child: Text(
                                  _memberInitial(member.displayName),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              title: Text(
                                member.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              trailing: member.isYou
                                  ? Text(
                                      Translations.getText('walkie_you', lang),
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    )
                                  : null,
                            ),
                            if (showDivider)
                              Divider(
                                height: 0,
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                          ],
                        );
                      }),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
