import 'package:flutter/material.dart';

import 'history_page.dart';
import 'receive_page.dart';
import 'send_page.dart';
import 'services_scope.dart';
import 'splash_screen.dart';
import 'theme.dart';

/// Main shell: Send / Receive / My drops.
///
/// Wide windows (desktop, tablets, large browsers) get a navigation rail;
/// narrow ones (phones, small windows) get a bottom navigation bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _destinations = [
    (icon: Icons.upload_outlined, selected: Icons.upload, label: 'Send'),
    (icon: Icons.download_outlined, selected: Icons.download, label: 'Receive'),
    (icon: Icons.history_outlined, selected: Icons.history, label: 'My drops'),
  ];

  final _historyKey = GlobalKey<HistoryPageState>();
  late int _index = widget.initialCode != null ? 1 : 0;
  bool _cleanedUp = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_cleanedUp) {
      _cleanedUp = true;
      // Best-effort: remove this user's expired/burned drops and their files.
      ServicesScope.of(context).drops.cleanup().catchError((_) => 0);
    }
  }

  void _select(int index) {
    setState(() => _index = index);
    if (index == 2) _historyKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.wide;
    final pages = IndexedStack(
      index: _index,
      children: [
        SendPage(dropEnabled: _index == 0),
        ReceivePage(initialCode: widget.initialCode),
        HistoryPage(key: _historyKey),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BurnerFlame(size: 26),
            SizedBox(width: 8),
            Text('Burner', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: const [_AccountMenu(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        top: false,
        child: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selected),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: pages),
                ],
              )
            : pages,
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: d.label,
                  ),
              ],
            ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context) {
    final auth = ServicesScope.of(context).auth;
    final email = auth.user?.email ?? '';
    return MenuAnchor(
      builder: (context, controller, _) => IconButton(
        tooltip: email,
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: CircleAvatar(
          radius: 16,
          child: Text(email.isEmpty ? '?' : email[0].toUpperCase()),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.person_outline),
          onPressed: null,
          child: Text(email),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: auth.signOut,
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
