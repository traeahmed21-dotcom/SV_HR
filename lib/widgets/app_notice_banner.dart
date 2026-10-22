import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_notice.dart';
import '../theme/app_semantic_colors.dart';
import 'scale_down_text.dart';

class AppNoticeBanner extends StatelessWidget {
  final AppNotice notice;
  final String lang;

  const AppNoticeBanner({
    super.key,
    required this.notice,
    required this.lang,
  });

  Future<void> _openLink(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  ({Color bg, Color fg, Color btnBg, Color btnFg, IconData icon}) _resolveStyle(
      ColorScheme scheme, AppSemanticColors? semantic) {
    final t = notice.noticeType.trim().toLowerCase();
    if (t == 'maintenance') {
      return (
        bg: semantic?.warningContainer ?? scheme.tertiaryContainer,
        fg: semantic?.onWarningContainer ?? scheme.onTertiaryContainer,
        btnBg: semantic?.warning ?? scheme.tertiary,
        btnFg: semantic?.onWarning ?? scheme.onTertiary,
        icon: Icons.build_circle_outlined,
      );
    }
    if (t == 'update') {
      return (
        bg: semantic?.infoContainer ?? scheme.primaryContainer,
        fg: semantic?.onInfoContainer ?? scheme.onPrimaryContainer,
        btnBg: semantic?.info ?? scheme.primary,
        btnFg: semantic?.onInfo ?? scheme.onPrimary,
        icon: Icons.system_update_alt_outlined,
      );
    }
    return (
      bg: semantic?.infoContainer ?? scheme.surfaceContainerHighest,
      fg: semantic?.onInfoContainer ?? scheme.onSurface,
      btnBg: semantic?.info ?? scheme.primary,
      btnFg: semantic?.onInfo ?? scheme.onPrimary,
      icon: Icons.info_outline,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    final style = _resolveStyle(scheme, semantic);
    final title = notice.titleFor(lang).trim();
    final message = notice.messageFor(lang).trim();
    final buttonText = notice.buttonTextFor(lang).trim();

    if (title.isEmpty && message.isEmpty) return const SizedBox();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: style.btnBg.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(style.icon, color: style.btnBg, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: style.fg,
                        ),
                  ),
                if (message.isNotEmpty) ...[
                  if (title.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: style.fg.withValues(alpha: 0.95),
                        ),
                  ),
                ],
                if (notice.hasAction) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: ElevatedButton(
                      onPressed: () => _openLink(notice.buttonUrl),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: style.btnBg,
                        foregroundColor: style.btnFg,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: ScaleDownText(
                        buttonText.isEmpty
                            ? (lang == 'ar' ? 'فتح' : 'Open')
                            : buttonText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
