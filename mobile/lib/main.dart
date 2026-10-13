import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/app_shell.dart';
import 'screens/company_select_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'theme.dart';
import 'utils/format.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(appLocale);
  runApp(SigcomApp(api: ApiService()));
}

class SigcomApp extends StatefulWidget {
  const SigcomApp({super.key, required this.api});

  final ApiService api;

  @override
  State<SigcomApp> createState() => _SigcomAppState();
}

class _SigcomAppState extends State<SigcomApp> {
  Map<String, dynamic>? _user;
  Company? _company;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      if (await widget.api.token != null) _user = await widget.api.me();
    } catch (_) {
      _user = null;
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } catch (_) {}
    setState(() {
      _user = null;
      _company = null;
    });
  }

  Widget _screen() {
    if (_checking) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final user = _user;
    if (user == null) {
      return LoginScreen(api: widget.api, onLoggedIn: (u) => setState(() => _user = u));
    }
    final company = _company;
    if (company == null) {
      return CompanySelectScreen(
        api: widget.api,
        user: user,
        onSelected: (c) => setState(() => _company = c),
        onLogout: _logout,
      );
    }
    return AppShell(
      api: widget.api,
      user: user,
      company: company,
      onChangeCompany: () => setState(() => _company = null),
      onLogout: _logout,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIGCOM Móvil',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _screen()),
    );
  }
}
