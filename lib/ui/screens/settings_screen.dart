import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/platform_info.dart';
import '../../core/storage/paired_devices_store.dart';
import '../../state/luch_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final LuchController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _serverController;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.controller.settings.deviceName);
    _serverController =
        TextEditingController(text: widget.controller.settings.serverOrigin);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _pickSaveFolder() async {
    final uri = await FilePicker.pickDirectory(
      dialogTitle: 'Выберите папку для сохранения файлов',
    );
    if (uri == null) return;
    final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
    if (path.isNotEmpty) {
      await widget.controller.updateSettings(customSaveDirectory: path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.settings;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Устройство и внешний вид',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Имя устройства',
                        ),
                        onSubmitted: (v) =>
                            c.updateSettings(deviceName: v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        c.updateSettings(deviceName: _nameController.text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Имя сохранено')),
                        );
                      },
                      child: const Text('Сохранить'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Тема оформления',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                SegmentedButton<AppThemePreference>(
                  segments: const [
                    ButtonSegment(
                      value: AppThemePreference.system,
                      label: Text('Система'),
                    ),
                    ButtonSegment(
                      value: AppThemePreference.dark,
                      label: Text('Тёмная'),
                    ),
                    ButtonSegment(
                      value: AppThemePreference.light,
                      label: Text('Светлая'),
                    ),
                  ],
                  selected: {s.theme},
                  onSelectionChanged: (sel) =>
                      c.updateSettings(theme: sel.first),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Принимать файлы автоматически'),
                subtitle: const Text(
                  'Не спрашивать подтверждение от сопряжённых и сканируемых устройств',
                ),
                value: s.autoAccept,
                onChanged: (val) => c.updateSettings(autoAccept: val),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Папка сохранения'),
                subtitle: Text(c.saveDirectoryDisplay),
                trailing: PlatformInfo.isWeb
                    ? null
                    : Wrap(
                        spacing: 6,
                        children: [
                          OutlinedButton(
                            onPressed: _pickSaveFolder,
                            child: const Text('Выбрать'),
                          ),
                          if (s.customSaveDirectory != null)
                            IconButton(
                              tooltip: 'Сбросить',
                              onPressed: () => c.updateSettings(
                                clearCustomSaveDirectory: true,
                              ),
                              icon: const Icon(Icons.restart_alt_rounded),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Сервер сигналинга и TURN',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Используется только для знакомства устройств по QR и ретрансляции при строгом NAT. Активно ICE-серверов: ${c.iceServersCount}.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _serverController,
                  decoration: const InputDecoration(
                    labelText: 'URL сервера «Луч»',
                    hintText: LuchSettings.defaultServerOrigin,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        await c.updateSettings(
                            serverOrigin: _serverController.text);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Сервер обновлён (ICE: ${c.iceServersCount})',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Применить и проверить'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        _serverController.text =
                            LuchSettings.defaultServerOrigin;
                        c.updateSettings(
                            serverOrigin: LuchSettings.defaultServerOrigin);
                      },
                      child: const Text('По умолчанию'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (c.devices.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Очистить сопряжённые устройства'),
              subtitle: Text('Сохранено устройств: ${c.devices.length}'),
              trailing: TextButton(
                onPressed: c.clearAllDevices,
                child: const Text('Очистить'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
