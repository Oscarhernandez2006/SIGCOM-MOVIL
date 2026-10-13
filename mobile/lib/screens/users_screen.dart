import 'package:flutter/material.dart';

import '../models/settings.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/status_pill.dart';
import '../widgets/web_session.dart';

const _red = Color(0xFFDC2626);

/// Configuración › Usuarios (solo administradores): cuentas, compañías, código Siesa y módulos.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, required this.api, required this.company, required this.user});

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  AdminUsersResult? _result;
  String? _error;
  String _query = '';
  String? _role;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final result = await widget.api.adminUsers(widget.company.id);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<AdminUser>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => UserFormSheet(api: widget.api, company: widget.company),
    );
    if (created == null || !mounted) return;
    await _load();
    if (mounted) _open(created);
  }

  Future<void> _open(AdminUser user) async {
    final result = _result;
    if (result == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserDetailScreen(
          api: widget.api,
          company: widget.company,
          currentUserId: widget.user['id'] as String?,
          companies: result.companies,
          user: user,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final q = _query.trim().toLowerCase();
    final users = (result?.users ?? const <AdminUser>[])
        .where((u) => _role == null || u.role == _role)
        .where(
          (u) =>
              q.isEmpty ||
              u.name.toLowerCase().contains(q) ||
              u.documentId.contains(q) ||
              (u.email?.toLowerCase().contains(q) ?? false),
        )
        .toList();

    return Stack(
      children: [
        const BrandBackground(),
        RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                sliver: SliverList.list(
                  children: [
                    _Header(
                      total: result?.users.length,
                      inactive: result?.users.where((u) => !u.active).length,
                      onSearch: (v) => setState(() => _query = v),
                      onCreate: result == null ? null : _create,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final role in [null, ...userRoles.keys])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  role == null
                                      ? 'Todos'
                                      : '${userRoles[role]} (${result?.users.where((u) => u.role == role).length ?? 0})',
                                ),
                                selected: _role == role,
                                backgroundColor: Colors.white,
                                onSelected: (_) => setState(() => _role = role),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_error != null) _Message(icon: Icons.cloud_off_rounded, text: _error!, onRetry: _load),
                  ],
                ),
              ),
              if (result == null && _error == null)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else if (result != null && users.isEmpty)
                const SliverToBoxAdapter(
                  child: _Message(icon: Icons.person_search_rounded, text: 'Ningún usuario coincide.'),
                )
              else if (result != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  sliver: SliverList.separated(
                    itemCount: users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _UserCard(user: users[i], onTap: () => _open(users[i])),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.total, required this.inactive, required this.onSearch, required this.onCreate});

  final int? total;
  final int? inactive;
  final ValueChanged<String> onSearch;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F6B35), AppColors.primary, Color(0xFF34B868)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Usuarios',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 40),
                ),
                onPressed: onCreate,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Nuevo', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          Text(
            total == null
                ? 'Cuentas de acceso a SIGCOM'
                : '$total usuarios${inactive == null || inactive == 0 ? '' : ' · $inactive inactivos'}',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Nombre, cédula o correo',
              isDense: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search_rounded),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onTap});

  final AdminUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Opacity(
            opacity: user.active ? 1 : 0.6,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(
                    user.name.trim().isEmpty ? '?' : user.name.trim()[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                      Text(
                        'CC ${user.documentId} · ${user.roleLabel}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (!user.active) const StatusPill(label: 'Inactivo', color: _red),
                          if (user.companies.isEmpty)
                            const StatusPill(label: 'Sin compañías', color: Color(0xFFEA580C))
                          else
                            for (final c in user.companies)
                              StatusPill(
                                label: c.sellerCode == null ? c.name : '${c.name} · ${c.sellerCode}',
                                color: AppColors.primary,
                                outlined: true,
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textSoft),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

/// Crear (sin [user]) o editar un usuario. Devuelve el usuario guardado.
class UserFormSheet extends StatefulWidget {
  const UserFormSheet({super.key, required this.api, required this.company, this.user});

  final ApiService api;
  final Company company;
  final AdminUser? user;

  @override
  State<UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<UserFormSheet> {
  final _form = GlobalKey<FormState>();
  late final _document = TextEditingController(text: widget.user?.documentId);
  late final _name = TextEditingController(text: widget.user?.name);
  late final _email = TextEditingController(text: widget.user?.email);
  final _password = TextEditingController();
  late String _role = widget.user?.role ?? 'seller';
  late bool _budget = widget.user?.clientBudget ?? false;
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.user != null;

  @override
  void dispose() {
    _document.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final fields = <String, Object?>{
      'document_id': _document.text.trim(),
      'name': _name.text.trim(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'role': _role,
      if (_role == 'seller') 'client_budget': _budget,
      if (_password.text.isNotEmpty) 'password': _password.text,
    };
    try {
      final saved = await withWebSession(
        context,
        widget.api,
        () => _editing
            ? widget.api.updateUser(widget.company.id, widget.user!.id, fields)
            : widget.api.createUser(widget.company.id, fields),
      );
      if (saved != null && mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _editing ? 'Editar usuario' : 'Nuevo usuario',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _document,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cédula (usuario de ingreso)'),
                validator: (v) => (v ?? '').trim().length < 4 ? 'Mínimo 4 caracteres' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Mínimo 2 caracteres' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo (opcional)'),
                validator: (v) {
                  final text = (v ?? '').trim();
                  return text.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)
                      ? null
                      : 'Correo no válido';
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Rol / área'),
                items: [for (final e in userRoles.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              if (_role == 'seller')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _budget,
                  onChanged: (v) => setState(() => _budget = v),
                  title: const Text('Presupuesto por cliente / tienda'),
                  subtitle: const Text('Su tablero muestra el presupuesto de cada cliente.'),
                ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: _editing ? 'Nueva contraseña (opcional)' : 'Contraseña',
                  helperText: _editing ? 'Déjala vacía para no cambiarla.' : null,
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  ),
                ),
                validator: (v) {
                  final text = v ?? '';
                  if (_editing && text.isEmpty) return null;
                  return text.length < 4 ? 'Mínimo 4 caracteres' : null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: _red, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        _editing ? 'Guardar cambios' : 'Crear usuario',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({
    super.key,
    required this.api,
    required this.company,
    required this.currentUserId,
    required this.companies,
    required this.user,
  });

  final ApiService api;
  final Company company;
  final String? currentUserId;
  final List<({String id, String name})> companies;
  final AdminUser user;

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  late AdminUser _user = widget.user;
  bool _busy = false;

  bool get _isSelf => _user.id == widget.currentUserId;

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<AdminUser> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      final user = await withWebSession(context, widget.api, action);
      if (user == null || !mounted) return;
      setState(() => _user = user);
      _snack(done);
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<AdminUser>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => UserFormSheet(api: widget.api, company: widget.company, user: _user),
    );
    if (saved != null && mounted) {
      setState(() => _user = saved);
      _snack('Usuario actualizado.');
    }
  }

  Future<void> _toggleActive(bool active) async {
    if (!active) {
      final ok = await _confirm(
        'Desactivar usuario',
        '${_user.name} no podrá ingresar a SIGCOM ni a la app hasta que lo actives de nuevo.',
        'Desactivar',
      );
      if (!ok) return;
    }
    await _run(
      () => widget.api.setUserActive(widget.company.id, _user.id, active),
      active ? 'Usuario activado.' : 'Usuario desactivado.',
    );
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      'Eliminar usuario',
      '¿Eliminar a ${_user.name} (CC ${_user.documentId})? Esta acción no se puede deshacer. '
          'Si solo quieres quitarle el acceso, desactívalo.',
      'Eliminar',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final done = await withWebSession(context, widget.api, () async {
        await widget.api.deleteUser(widget.company.id, _user.id);
        return true;
      });
      if (done == true && mounted) {
        _snack('Usuario eliminado.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _openAccess(({String id, String name}) company) async {
    final access = _user.companies.where((c) => c.id == company.id).firstOrNull;
    final result = await Navigator.of(context).push<AdminUser>(
      MaterialPageRoute(
        builder: (_) => CompanyAccessScreen(
          api: widget.api,
          company: widget.company,
          user: _user,
          target: company,
          access: access,
          isSelf: _isSelf,
        ),
      ),
    );
    if (result != null && mounted) setState(() => _user = result);
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final assigned = {for (final c in user.companies) c.id: c};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuario', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Editar', onPressed: _busy ? null : _edit, icon: const Icon(Icons.edit_outlined)),
          if (!_isSelf)
            IconButton(
              tooltip: 'Eliminar',
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: _red),
            ),
        ],
        bottom: _busy
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _Section(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('CC ${user.documentId} · ${user.roleLabel}', style: const TextStyle(color: AppColors.textSoft)),
                if (user.email != null) Text(user.email!, style: const TextStyle(color: AppColors.textSoft)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (user.role == 'seller' && user.clientBudget)
                      const StatusPill(label: 'Presupuesto por cliente', color: AppColors.primary, outlined: true),
                    if (user.mustChangePassword)
                      const StatusPill(label: 'Debe cambiar la contraseña', color: Color(0xFFEA580C), outlined: true),
                  ],
                ),
                if (user.passwordChangedAt != null || user.createdAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (user.createdAt != null) 'Creado ${formatShortDate(user.createdAt!)}',
                      if (user.passwordChangedAt != null)
                        'contraseña cambiada ${formatShortDate(user.passwordChangedAt!)}',
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.textSoft, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: user.active,
              onChanged: _busy || _isSelf || user.role == 'admin' ? null : _toggleActive,
              title: const Text('Usuario activo', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                _isSelf
                    ? 'No puedes desactivar tu propio usuario.'
                    : user.role == 'admin'
                    ? 'Los administradores no se desactivan (igual que en la web).'
                    : user.active
                    ? 'Puede ingresar a SIGCOM y a la app.'
                    : 'No puede ingresar.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'COMPAÑÍAS Y MÓDULOS',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
            ),
          ),
          for (final company in widget.companies) ...[
            _CompanyTile(
              name: company.name,
              access: assigned[company.id],
              enabled: !_busy,
              onTap: () => _openAccess(company),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({required this.name, required this.access, required this.enabled, required this.onTap});

  final String name;
  final UserCompanyAccess? access;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = access;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        enabled: enabled,
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        leading: Icon(
          a == null ? Icons.add_business_outlined : Icons.apartment_rounded,
          color: a == null ? AppColors.textSoft : AppColors.primary,
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          a == null
              ? 'Sin acceso · toca para asignar'
              : [
                  if (a.sellerCode != null) 'Código Siesa ${a.sellerCode}',
                  a.permissions.isEmpty ? 'módulos del rol' : '${a.permissions.length} módulos',
                ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Acceso del usuario a una compañía: código de vendedor Siesa y módulos permitidos.
class CompanyAccessScreen extends StatefulWidget {
  const CompanyAccessScreen({
    super.key,
    required this.api,
    required this.company,
    required this.user,
    required this.target,
    required this.access,
    required this.isSelf,
  });

  final ApiService api;
  final Company company;
  final AdminUser user;
  final ({String id, String name}) target;
  final UserCompanyAccess? access;
  final bool isSelf;

  @override
  State<CompanyAccessScreen> createState() => _CompanyAccessScreenState();
}

class _CompanyAccessScreenState extends State<CompanyAccessScreen> {
  late final _code = TextEditingController(text: widget.access?.sellerCode);
  late final Set<String> _permissions = {...?widget.access?.permissions};
  bool _saving = false;

  bool get _assigned => widget.access != null;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final user = await withWebSession(context, widget.api, () async {
        final code = _code.text.trim();
        var user = await widget.api.assignUserCompany(
          widget.company.id,
          widget.user.id,
          widget.target.id,
          code.isEmpty ? null : code,
        );
        final current = {...?widget.access?.permissions};
        if (current.length != _permissions.length || !current.containsAll(_permissions)) {
          user = await widget.api.saveUserPermissions(
            widget.company.id,
            widget.user.id,
            widget.target.id,
            _permissions.toList(),
          );
        }
        return user;
      });
      if (user != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Acceso a ${widget.target.name} guardado.')));
        Navigator.pop(context, user);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar acceso'),
        content: Text('${widget.user.name} dejará de ver ${widget.target.name}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final user = await withWebSession(
        context,
        widget.api,
        () => widget.api.removeUserCompany(widget.company.id, widget.user.id, widget.target.id),
      );
      if (user != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Se quitó el acceso a ${widget.target.name}.')));
        Navigator.pop(context, user);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRemove = _assigned && !(widget.isSelf && widget.target.id == widget.company.id);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.target.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text(widget.user.name, style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
          ],
        ),
        actions: [
          if (canRemove)
            TextButton(
              onPressed: _saving ? null : _remove,
              style: TextButton.styleFrom(foregroundColor: _red),
              child: const Text('Quitar acceso'),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    _assigned ? 'Guardar acceso' : 'Asignar compañía',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            controller: _code,
            decoration: const InputDecoration(
              labelText: 'Código de vendedor Siesa',
              helperText: 'Define qué clientes ve como vendedor en esta compañía.',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _permissions.isEmpty ? 'Módulos: los del rol' : 'Módulos: ${_permissions.length} seleccionados',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _permissions.addAll([for (final g in permissionGroups) ...g.modules.map((m) => m.key)]),
                ),
                child: const Text('Todos'),
              ),
              TextButton(onPressed: () => setState(_permissions.clear), child: const Text('Ninguno')),
            ],
          ),
          const Text(
            'Sin módulos seleccionados se usan los predeterminados del rol.',
            style: TextStyle(color: AppColors.textSoft, fontSize: 12.5),
          ),
          for (final group in permissionGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(
                group.title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Material(
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              child: Column(
                children: [
                  for (final m in group.modules)
                    CheckboxListTile(
                      dense: true,
                      value: _permissions.contains(m.key),
                      onChanged: (v) =>
                          setState(() => v == true ? _permissions.add(m.key) : _permissions.remove(m.key)),
                      title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
