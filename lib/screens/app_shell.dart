import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart' as api_models;
import '../models/employee.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import 'home_screen.dart';
import 'requests_screen.dart';
import 'employee_chats_screen.dart';
import 'user_tasks_screen.dart';
import 'profile_screen.dart';

class AppShell extends StatefulWidget {
  final String employeeNumber;
  final api_models.EmployeeData employeeData;

  const AppShell({
    super.key,
    required this.employeeNumber,
    required this.employeeData,
  });

  static void selectTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_AppShellState>();
    state?._onDestinationSelected(index);
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const int _tabCount = 5;
  late List<GlobalKey<NavigatorState>> _navigatorKeys;

  int _unreadChats = 0;
  int _pendingRequests = 0;
  int _pendingTasks = 0;
  DateTime? _lastBackPressAt;

  @override
  void initState() {
    super.initState();
    _navigatorKeys = List.generate(
      _tabCount,
      (_) => GlobalKey<NavigatorState>(),
    );
    _refreshBadges();
  }

  String _lang(BuildContext context) =>
      context.read<LanguageService>().currentLocale.languageCode;

  String _t(BuildContext context, String key) => Translations.getText(key, _lang(context));

  Employee _asEmployee(BuildContext context) {
    final lang = _lang(context);
    return Employee(
      id: widget.employeeData.employeeID.toString(),
      name: widget.employeeData.name,
      email: widget.employeeData.email,
      position:
          '${Translations.getText('employee_number_short', lang)}: ${widget.employeeData.employeeNumber}',
      department: '',
      phone: '',
      employeeNumber: widget.employeeData.employeeNumber,
      hireDate: DateTime.now(),
      salary: 0,
    );
  }

  Future<void> _refreshBadges() async {
    final clientId = widget.employeeData.clientID;
    final employeeId = widget.employeeData.employeeID;

    final unreadChats =
        await ApiService.getChatUnreadCount(clientId, employeeId).catchError((_) {
      return 0;
    });

    final pendingCounts = await ApiService.getPendingCounts(clientId, employeeId);
    final pendingRequests = pendingCounts == null
        ? 0
        : (pendingCounts.leave + pendingCounts.loan + pendingCounts.other);

    final pendingTasks = await ApiService.getUserTasks(
      clientId,
      employeeId: employeeId,
      status: 'Pending',
      page: 1,
      pageSize: 200,
    ).then<int>((resp) {
      if (resp['Success'] != true) return 0;
      final data = resp['Data'];
      if (data is List) return data.length;
      return 0;
    }).catchError((_) {
      return 0;
    });

    if (!mounted) return;
    setState(() {
      _unreadChats = unreadChats;
      _pendingRequests = pendingRequests;
      _pendingTasks = pendingTasks;
    });
  }

  Widget _maybeBadge(int count, Widget child) {
    if (count <= 0) return child;
    return Badge(label: Text('$count'), child: child);
  }

  void _onDestinationSelected(int newIndex) {
    if (newIndex < 0 || newIndex >= _navigatorKeys.length) return;
    if (newIndex == _index) {
      _navigatorKeys[newIndex].currentState?.popUntil((r) => r.isFirst);
      _refreshBadges();
      return;
    }
    setState(() => _index = newIndex);
    _refreshBadges();
  }

  Route<dynamic> _onGenerateRoute(int tabIndex, RouteSettings settings) {
    Widget page;
    switch (tabIndex) {
      case 0:
        page = HomeScreen(
          employeeId: widget.employeeNumber,
          employeeData: widget.employeeData,
        );
        break;
      case 1:
        page = RequestsScreen(
          employeeId: widget.employeeNumber,
          employeeData: widget.employeeData,
        );
        break;
      case 2:
        page = EmployeeChatsScreen(
          clientId: widget.employeeData.clientID,
          employeeId: widget.employeeData.employeeID,
          employeeName: widget.employeeData.name,
        );
        break;
      case 3:
        page = UserTasksScreen(
          clientId: widget.employeeData.clientID,
          employeeId: widget.employeeData.employeeID,
        );
        break;
      case 4:
        page = ProfileScreen(
          employee: _asEmployee(context),
          clientId: widget.employeeData.clientID,
        );
        break;
      default:
        page = const SizedBox.shrink();
    }
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }

  Future<bool> _onWillPop(BuildContext context) async {
    final nav = _navigatorKeys[_index].currentState;
    if (nav != null) {
      final didPop = await nav.maybePop();
      if (didPop) return false;
    }

    if (_index != 0) {
      setState(() => _index = 0);
      return false;
    }

    final now = DateTime.now();
    final last = _lastBackPressAt;
    final allowExit =
        last != null && now.difference(last) <= const Duration(seconds: 2);
    if (allowExit) return true;

    _lastBackPressAt = now;
    final lang = _lang(context);
    final message = lang == 'ar'
        ? 'اضغط رجوع مرة أخرى للخروج'
        : 'Press back again to exit';
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_navigatorKeys.length != _tabCount) {
      _navigatorKeys = List.generate(
        _tabCount,
        (_) => GlobalKey<NavigatorState>(),
      );
      if (_index >= _tabCount) {
        _index = 0;
      }
    }

    return WillPopScope(
      onWillPop: () => _onWillPop(context),
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: List.generate(
            _tabCount,
            (i) => Navigator(
              key: _navigatorKeys[i],
              onGenerateRoute: (settings) => _onGenerateRoute(i, settings),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          height: 72,
          selectedIndex: _index,
          onDestinationSelected: _onDestinationSelected,
          backgroundColor: Theme.of(context).navigationBarTheme.backgroundColor,
          indicatorColor: scheme.primaryContainer,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: const Icon(Icons.dashboard),
              label: _t(context, 'home'),
            ),
            NavigationDestination(
              icon: _maybeBadge(
                _pendingRequests,
                const Icon(Icons.assignment_outlined),
              ),
              selectedIcon: _maybeBadge(
                _pendingRequests,
                const Icon(Icons.assignment),
              ),
              label: _t(context, 'requests'),
            ),
            NavigationDestination(
              icon: _maybeBadge(
                _unreadChats,
                const Icon(Icons.chat_bubble_outline),
              ),
              selectedIcon: _maybeBadge(
                _unreadChats,
                const Icon(Icons.chat_bubble),
              ),
              label: _t(context, 'employee_chats'),
            ),
            NavigationDestination(
              icon: _maybeBadge(
                _pendingTasks,
                const Icon(Icons.task_alt_outlined),
              ),
              selectedIcon: _maybeBadge(
                _pendingTasks,
                const Icon(Icons.task_alt),
              ),
              label: _t(context, 'tasks_title'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: _t(context, 'profile'),
            ),
          ],
        ),
      ),
    );
  }
}
