import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';

typedef ModuleVisibility = bool Function(Map<String, dynamic> user, Company company);

bool _always(Map<String, dynamic> user, Company company) => true;
bool _admin(Map<String, dynamic> user, Company company) => user['role'] == 'admin';
bool _staff(Map<String, dynamic> user, Company company) => user['role'] != 'seller';
bool _approver(Map<String, dynamic> user, Company company) => company.canApprove;
bool _subproducts(Map<String, dynamic> user, Company company) => company.canControlSubproducts;
bool _priceLists(Map<String, dynamic> user, Company company) => company.canPriceLists;
bool _featured(Map<String, dynamic> user, Company company) => company.canFeaturedProducts;
bool _clients(Map<String, dynamic> user, Company company) => company.canClients;
bool _schedule(Map<String, dynamic> user, Company company) => company.canSchedule;
bool _users(Map<String, dynamic> user, Company company) => company.canUsers;

enum AppModule {
  dashboardComercial('Dashboard comercial', Icons.space_dashboard_rounded),
  pedidos('Pedidos', Icons.receipt_long_rounded),
  cotizaciones('Cotizaciones', Icons.request_quote_rounded),
  cartera('Cartera de clientes', Icons.account_balance_wallet_rounded),
  disponibilidad('Disponibilidad', Icons.inventory_2_rounded),
  panelControl('Panel de control', Icons.dashboard_rounded, _admin),
  negociosNacionales('Negocios nacionales', Icons.public_rounded, _admin),
  reportes('Reportes', Icons.assessment_rounded, _admin),
  seguimientoPedidos('Seguimiento de pedidos', Icons.manage_search_rounded, _staff),
  aprobacionCartera('Aprobación de cartera', Icons.price_check_rounded, _approver),
  controlSubproductos('Control de subproductos', Icons.rule_rounded, _subproducts),
  listasPrecios('Listas de precios', Icons.sell_rounded, _priceLists),
  productosEstrella('Productos estrella', Icons.star_rounded, _featured),
  clientes('Clientes', Icons.groups_rounded, _clients),
  horario('Horario de pedidos', Icons.schedule_rounded, _schedule),
  usuarios('Usuarios', Icons.manage_accounts_rounded, _users);

  const AppModule(this.title, this.icon, [this.visible = _always]);

  final String title;
  final IconData icon;

  /// Rol del usuario o permisos de la compañía activa (flags de /companies).
  final ModuleVisibility visible;
}

class _MenuSection {
  const _MenuSection(this.title, this.icon, [this.modules = const []]);

  final String title;
  final IconData icon;
  final List<AppModule> modules;

  _MenuSection visibleFor(Map<String, dynamic> user, Company company) =>
      _MenuSection(title, icon, modules.where((m) => m.visible(user, company)).toList());
}

const _sections = [
  _MenuSection('Operativo', Icons.insights_rounded, [
    AppModule.dashboardComercial,
    AppModule.pedidos,
    AppModule.cotizaciones,
    AppModule.cartera,
    AppModule.disponibilidad,
  ]),
  _MenuSection('General', Icons.grid_view_rounded, [
    AppModule.panelControl,
    AppModule.negociosNacionales,
    AppModule.reportes,
  ]),
  _MenuSection('Aprobación y control', Icons.fact_check_rounded, [
    AppModule.aprobacionCartera,
    AppModule.controlSubproductos,
    AppModule.seguimientoPedidos,
  ]),
  _MenuSection('Catálogo', Icons.inventory_2_rounded, [
    AppModule.clientes,
    AppModule.listasPrecios,
    AppModule.productosEstrella,
  ]),
  _MenuSection('Configuración', Icons.settings_rounded, [AppModule.horario, AppModule.usuarios]),
];

const _roleLabels = {
  'admin': 'Administrador',
  'seller': 'Vendedor',
  'cartera': 'Cartera',
  'alistador': 'Alistador',
  'facturacion': 'Facturación',
};

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.user,
    required this.company,
    required this.current,
    required this.onSelect,
    required this.onChangeCompany,
    required this.onLogout,
  });

  final Map<String, dynamic> user;
  final Company company;
  final AppModule current;
  final ValueChanged<AppModule> onSelect;
  final VoidCallback onChangeCompany;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(28))),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Brand(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: _CompanyCard(company: company, onChange: onChangeCompany),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final section in _sections)
                    _SectionTile(section: section.visibleFor(user, company), current: current, onSelect: onSelect),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            _UserFooter(user: user, onLogout: onLogout),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Image.asset('assets/images/sigcom_logo.png', height: 58, semanticLabel: 'SIGCOM'),
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.company, required this.onChange});

  final Company company;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onChange,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Image.asset(company.logoAsset, fit: BoxFit.contain),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (company.codeLabel != null)
                      Text(
                        'Compañía ${company.id}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSoft),
                      ),
                    Text(
                      company.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text),
                    ),
                  ],
                ),
              ),
              const Tooltip(
                message: 'Cambiar compañía',
                child: Icon(Icons.sync_alt_rounded, color: AppColors.primary, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.current, required this.onSelect});

  final _MenuSection section;
  final AppModule current;
  final ValueChanged<AppModule> onSelect;

  @override
  Widget build(BuildContext context) {
    final active = section.modules.contains(current);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: active,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.only(left: 8, bottom: 6),
        leading: Icon(section.icon, size: 22, color: active ? AppColors.primary : AppColors.textSoft),
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.textSoft,
        title: Text(
          section.title.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: active ? AppColors.primary : AppColors.textMuted,
          ),
        ),
        children: [
          if (section.modules.isEmpty)
            const ListTile(
              dense: true,
              enabled: false,
              leading: Icon(Icons.schedule_rounded, size: 20),
              title: Text('Próximamente'),
            ),
          for (final module in section.modules)
            _ModuleTile(module: module, selected: module == current, onTap: () => onSelect(module)),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module, required this.selected, required this.onTap});

  final AppModule module;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: AppColors.primary.withValues(alpha: 0.1),
        selectedColor: AppColors.primary,
        iconColor: AppColors.textSoft,
        textColor: AppColors.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(module.icon, size: 20),
        title: Text(module.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        onTap: onTap,
      ),
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter({required this.user, required this.onLogout});

  final Map<String, dynamic> user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] as String? ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
                ),
                Text(
                  _roleLabels[user['role']] ?? '${user['role'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded, color: AppColors.textMuted),
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}
