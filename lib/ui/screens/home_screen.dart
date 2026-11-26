import 'package:material_ui/material_ui.dart';

import '../../state/luch_controller.dart';
import '../theme/app_theme.dart';
import 'devices_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';
import 'settings_screen.dart';

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
        final isWide = MediaQuery.sizeOf(context).width >= 800;
        final c = widget.controller;
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final pages = [
          SendScreen(controller: c),
          ReceiveScreen(controller: c),
          DevicesScreen(
            controller: c,
            onJumpToSend: () => setState(() => _tabIndex = 0),
          ),
          SettingsScreen(controller: c),
        ];

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 16,
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/luch_icon.png',
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
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
                      c.settings.deviceName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _PresencePill(
                  online: c.presenceStatus == 'online' ||
                      c.signalingStatus == 'online',
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (c.incomingCall != null)
                MaterialBanner(
                  backgroundColor: cs.primary.withValues(alpha: 0.14),
                  leading: Icon(Icons.ring_volume_rounded, color: cs.primary),
                  content: Text(
                    'Устройство «${c.incomingCall!.fromDevice}» запрашивает подключение.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: c.rejectIncomingCall,
                      child: const Text('Отклонить'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        c.acceptIncomingCall();
                        setState(() => _tabIndex = 1);
                      },
                      child: const Text('Принять'),
                    ),
                  ],
                ),
              Expanded(
                child: Row(
                  children: [
                    if (isWide)
                      NavigationRail(
                        backgroundColor:
                            isDark ? AppTheme.surface : AppTheme.lightSurface,
                        selectedIndex: _tabIndex,
                        onDestinationSelected: (idx) =>
                            setState(() => _tabIndex = idx),
                        labelType: NavigationRailLabelType.all,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.north_east_rounded),
                            label: Text('Отправить'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.south_west_rounded),
                            label: Text('Принять'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.devices_rounded),
                            label: Text('Устройства'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings_outlined),
                            label: Text('Настройки'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 840),
                          child: IndexedStack(
                            index: _tabIndex,
                            children: pages,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  backgroundColor:
                      isDark ? AppTheme.surface : AppTheme.lightSurface,
                  selectedIndex: _tabIndex,
                  onDestinationSelected: (idx) =>
                      setState(() => _tabIndex = idx),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.north_east_rounded),
                      label: 'Отправить',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.south_west_rounded),
                      label: 'Принять',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.devices_rounded),
                      label: 'Устройства',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      label: 'Настройки',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _PresencePill extends StatelessWidget {
  const _PresencePill({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = online ? AppTheme.success : Theme.of(context).hintColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            online ? 'В сети' : 'Готов',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
