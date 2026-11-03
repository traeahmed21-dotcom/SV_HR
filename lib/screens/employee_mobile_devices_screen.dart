import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../widgets/custom_card.dart';
import '../widgets/scale_down_text.dart';

class EmployeeMobileDevicesScreen extends StatefulWidget {
  final int clientId;

  const EmployeeMobileDevicesScreen({
    super.key,
    required this.clientId,
  });

  @override
  State<EmployeeMobileDevicesScreen> createState() =>
      _EmployeeMobileDevicesScreenState();
}

class _EmployeeMobileDevicesScreenState extends State<EmployeeMobileDevicesScreen>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  bool _loading = false;
  int _totalCount = 0;
  List<Map<String, dynamic>> _items = [];
  String? _errorMessage;
  Timer? _searchDebounce;

  String _t(BuildContext context, String key) {
    final lang = context.read<LanguageService>().currentLocale.languageCode;
    return Translations.getText(key, lang);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      _load();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final resp = await ApiService.getEmployeeMobileDevices(
        widget.clientId,
        search: _searchController.text.trim(),
        page: 1,
        pageSize: 200,
      );
      if (!mounted) return;
      final ok = resp['Success'] == true;
      final data = ok ? (resp['Data'] as List?) : null;
      setState(() {
        _items = data is List
            ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];
        _totalCount = (resp['TotalCount'] is int) ? resp['TotalCount'] as int : _items.length;
        _errorMessage = ok ? null : (resp['Message']?.toString().trim().isNotEmpty == true ? resp['Message'].toString() : _t(context, 'unexpected_error'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = _t(context, 'unexpected_error');
      });
    }
  }

  Future<void> _setActive(Map<String, dynamic> item, bool isActive) async {
    final employeeId = (item['EmployeeID'] is int) ? item['EmployeeID'] as int : 0;
    final mac = (item['MACAddress'] ?? '').toString();
    if (employeeId <= 0 || mac.isEmpty) return;
    final ok = await ApiService.setEmployeeMobileDeviceActive(
      widget.clientId,
      employeeId: employeeId,
      macAddress: mac,
      isActive: isActive,
    );
    if (!mounted) return;
    if (ok) {
      await _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final employeeId = (item['EmployeeID'] is int) ? item['EmployeeID'] as int : 0;
    final mac = (item['MACAddress'] ?? '').toString();
    if (employeeId <= 0 || mac.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(_t(ctx, 'confirm_delete')),
          content: Text('${_t(ctx, 'device')}: $mac'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(_t(ctx, 'cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
              ),
              child: Text(_t(ctx, 'delete')),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final ok = await ApiService.deleteEmployeeMobileDevice(
      widget.clientId,
      employeeId: employeeId,
      macAddress: mac,
    );
    if (!mounted) return;
    if (ok) {
      await _load();
    }
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final scheme = Theme.of(context).colorScheme;
    final employeeName = (item['EmployeeName'] ?? '').toString();
    final employeeNumber = (item['EmployeeNumber'] ?? '').toString();
    final mac = (item['MACAddress'] ?? '').toString();
    final deviceName = (item['DeviceName'] ?? '').toString();
    final deviceType = (item['DeviceType'] ?? '').toString();
    final isActive = item['IsActive'] == true;
    final firstLogin = (item['FirstLoginDate'] ?? '').toString();
    final lastLogin = (item['LastLoginDate'] ?? '').toString();
    final loginCount = item['LoginCount'] is int ? item['LoginCount'] as int : 0;
    final title = employeeName.isEmpty ? employeeNumber : employeeName;
    final subtitle = employeeNumber.isEmpty ? mac : '$employeeNumber • $mac';
    final deviceLine = [deviceName, deviceType]
        .where((e) => e.trim().isNotEmpty)
        .join(' • ');
    final isDark = scheme.brightness == Brightness.dark;
    final borderColor = scheme.outlineVariant.withValues(alpha: isDark ? 0.55 : 0.45);

    return CustomCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      borderRadius: 22,
      gloss: true,
      border: BorderSide(color: borderColor, width: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.phonelink_setup_rounded,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ScaleDownText(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    ScaleDownText(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: '',
                onSelected: (v) async {
                  if (v == 'toggle') {
                    await _setActive(item, !isActive);
                    return;
                  }
                  if (v == 'delete') {
                    await _delete(item);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          isActive
                              ? Icons.pause_circle_outline_rounded
                              : Icons.play_circle_outline_rounded,
                          size: 18,
                          color: scheme.onSurface,
                        ),
                        const SizedBox(width: 10),
                        Text(isActive
                            ? _t(ctx, 'deactivate')
                            : _t(ctx, 'activate')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 10),
                        Text(_t(ctx, 'delete')),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? scheme.tertiaryContainer
                        : scheme.errorContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive
                            ? Icons.verified_rounded
                            : Icons.warning_amber_rounded,
                        size: 16,
                        color: isActive
                            ? scheme.onTertiaryContainer
                            : scheme.onErrorContainer,
                      ),
                      const SizedBox(width: 6),
                      ScaleDownText(
                        isActive ? _t(context, 'active') : _t(context, 'inactive'),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: isActive
                                  ? scheme.onTertiaryContainer
                                  : scheme.onErrorContainer,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (deviceLine.isNotEmpty) ...[
            ScaleDownText(
              deviceLine,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (lastLogin.isNotEmpty)
                _InfoChip(
                  icon: Icons.schedule_rounded,
                  text: '${_t(context, 'last_login')}: $lastLogin',
                ),
              if (firstLogin.isNotEmpty)
                _InfoChip(
                  icon: Icons.history_rounded,
                  text: '${_t(context, 'first_login')}: $firstLogin',
                ),
              _InfoChip(
                icon: Icons.numbers_rounded,
                text: '${_t(context, 'login_count')}: $loginCount',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _loading ? null : () => _delete(item),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(_t(context, 'delete')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_t(context, 'employee_mobile_devices_title')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      hintText: _t(context, 'search'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: '',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                                _load();
                              },
                            ),
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) {
                      setState(() {});
                      _onSearchChanged(v);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: ScaleDownText(
                    '${_t(context, 'total')}: $_totalCount',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading && _items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [
                            const SizedBox(height: 64),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.phonelink_erase_rounded,
                                    size: 44,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 12),
                                  ScaleDownText(
                                    _errorMessage?.isNotEmpty == true
                                        ? _errorMessage!
                                        : _t(context,
                                            'employee_mobile_devices_empty'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemBuilder: (ctx, i) => _buildItem(_items[i]),
                          separatorBuilder: (ctx, i) =>
                              const SizedBox(height: 12),
                          itemCount: _items.length,
                        ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          ScaleDownText(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
