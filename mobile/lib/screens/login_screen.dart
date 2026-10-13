import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/credentials_store.dart';
import '../theme.dart';
import '../widgets/brand_background.dart';

class LoginScreen extends StatefulWidget {
  LoginScreen({super.key, required this.api, required this.onLoggedIn, CredentialsStore? credentials})
    : credentials = credentials ?? CredentialsStore();

  final ApiService api;
  final ValueChanged<Map<String, dynamic>> onLoggedIn;
  final CredentialsStore credentials;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _document = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  bool _obscure = true;
  bool _remember = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await widget.credentials.read();
    if (saved == null || !mounted) return;
    setState(() {
      _document.text = saved.document;
      _password.text = saved.password;
      _remember = true;
    });
  }

  @override
  void dispose() {
    _document.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final document = _document.text.trim();
      final user = await widget.api.login(document, _password.text);
      if (_remember) {
        await widget.credentials.save(document, _password.text);
      } else {
        await widget.credentials.clear();
      }
      widget.onLoggedIn(user);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const BrandBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 840;
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                    child: Center(child: FadeSlideIn(child: wide ? _wideLayout() : _compactLayout())),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactLayout() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/sigcom_logo.png', height: 96),
          const SizedBox(height: 24),
          _card(),
          const SizedBox(height: 24),
          const _LogosHeader(),
          const SizedBox(height: 20),
          _footer(),
        ],
      ),
    );
  }

  Widget _wideLayout() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/logo_santacruz.png', width: 240),
        const SizedBox(width: 56),
        SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/sigcom_logo.png', height: 96),
              const SizedBox(height: 24),
              _card(),
              const SizedBox(height: 24),
              _footer(),
            ],
          ),
        ),
        const SizedBox(width: 56),
        Image.asset('assets/images/logo_carnesfrias.png', width: 170),
      ],
    );
  }

  Widget _card() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.08), blurRadius: 40, offset: const Offset(0, 16)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bienvenido',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ingresa tus credenciales para acceder al sistema.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 28),
              const _FieldLabel('Cédula'),
              TextFormField(
                controller: _document,
                enabled: !_loading,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(hintText: 'Número de cédula', prefixIcon: Icon(Icons.badge_outlined)),
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa tu número de cédula' : null,
              ),
              const SizedBox(height: 20),
              const _FieldLabel('Contraseña'),
              TextFormField(
                controller: _password,
                focusNode: _passwordFocus,
                enabled: !_loading,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) => (v == null || v.isEmpty) ? 'Ingresa tu contraseña' : null,
              ),
              const SizedBox(height: 6),
              _RememberCheck(value: _remember, onChanged: _loading ? null : (v) => setState(() => _remember = v)),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _error == null ? const SizedBox(width: double.infinity) : _ErrorBanner(_error!),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _loading
                      ? const Row(
                          key: ValueKey('loading'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            ),
                            SizedBox(width: 12),
                            Text('Ingresando...'),
                          ],
                        )
                      : const Row(
                          key: ValueKey('idle'),
                          mainAxisSize: MainAxisSize.min,
                          children: [Icon(Icons.login_rounded, size: 22), SizedBox(width: 10), Text('Ingresar')],
                        ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '¿Problemas para acceder? Contacta al administrador del sistema.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'SIGCOM · Sistema de Gestión Comercial',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '«Encomienda a Jehová tus obras, y tus pensamientos serán afirmados.»',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSoft,
            fontStyle: FontStyle.italic,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Proverbios 16:3',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSoft, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _LogosHeader extends StatelessWidget {
  const _LogosHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: Image.asset('assets/images/logo_santacruz.png', height: 56)),
        Container(width: 1, height: 40, margin: const EdgeInsets.symmetric(horizontal: 20), color: AppColors.border),
        Flexible(child: Image.asset('assets/images/logo_carnesfrias.png', height: 56)),
      ],
    );
  }
}

class _RememberCheck extends StatelessWidget {
  const _RememberCheck({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
                activeColor: AppColors.primary,
                side: const BorderSide(color: AppColors.textSoft, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Recordar contraseña',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: error, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
