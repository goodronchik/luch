import 'package:material_ui/material_ui.dart';

import '../../state/luch_controller.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final LuchController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final isWide = MediaQuery.sizeOf(context).width >= 760;
        final c = widget.controller;

        final pages = [
          SendScreen(controller: c),
          ReceiveScreen(controller: c),
          HistoryScreen(controller: c),
        ];

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppTheme.bg,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 16,
            title: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.accent, AppTheme.amber],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFF061322),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Луч',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                    Text(
                      '${c.deviceName}${c.selectedInterface != null ? " • ${c.selectedInterface!.ipAddress}" : ""}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Обновить сетевые адреса',
                onPressed: c.refreshInterfaces,
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: Row(
            children: [
              if (isWide)
                NavigationRail(
                  backgroundColor: AppTheme.surface,
                  selectedIndex: _tabIndex,
                  onDestinationSelected: (idx) =>
                      setState(() => _tabIndex = idx),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.upload_rounded),
                      label: Text('Отправить'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.qr_code_scanner_rounded),
                      label: Text('Принять'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.history_rounded),
                      label: Text('История'),
                    ),
                  ],
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: IndexedStack(
                      index: _tabIndex,
                      children: pages,
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  backgroundColor: AppTheme.surface,
                  selectedIndex: _tabIndex,
                  onDestinationSelected: (idx) =>
                      setState(() => _tabIndex = idx),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.upload_rounded),
                      label: 'Отправить',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.qr_code_scanner_rounded),
                      label: 'Принять',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.history_rounded),
                      label: 'История',
                    ),
                  ],
                ),
        );
      },
    );
  }
}
