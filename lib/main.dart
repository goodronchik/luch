import 'package:material_ui/material_ui.dart';

import 'state/luch_controller.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LuchApp());
}

class LuchApp extends StatefulWidget {
  const LuchApp({super.key});

  @override
  State<LuchApp> createState() => _LuchAppState();
}

class _LuchAppState extends State<LuchApp> {
  final LuchController _controller = LuchController();

  @override
  void initState() {
    super.initState();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Луч',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: HomeScreen(controller: _controller),
    );
  }
}
