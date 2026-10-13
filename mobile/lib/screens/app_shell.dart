import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/app_drawer.dart';
import 'approvals_screen.dart';
import 'availability_screen.dart';
import 'clients_screen.dart';
import 'dashboard_screen.dart';
import 'featured_products_screen.dart';
import 'managerial_screen.dart';
import 'orders_screen.dart';
import 'portfolio_screen.dart';
import 'price_lists_screen.dart';
import 'quotes_screen.dart';
import 'reports_screen.dart';
import 'schedule_screen.dart';
import 'subproduct_control_screen.dart';
import 'users_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.api,
    required this.user,
    required this.company,
    required this.onChangeCompany,
    required this.onLogout,
  });

  final ApiService api;
  final Map<String, dynamic> user;
  final Company company;
  final VoidCallback onChangeCompany;
  final VoidCallback onLogout;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppModule _module = AppModule.dashboardComercial;

  void _select(AppModule module) {
    Navigator.of(context).pop();
    setState(() => _module = module);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Image.asset('assets/images/sigcom_icon.png', height: 34, semanticLabel: 'SIGCOM'),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_module.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Row(
              children: [
                const Icon(Icons.apartment_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    widget.company.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      drawer: AppDrawer(
        user: widget.user,
        company: widget.company,
        current: _module,
        onSelect: _select,
        onChangeCompany: widget.onChangeCompany,
        onLogout: widget.onLogout,
      ),
      body: switch (_module) {
        AppModule.dashboardComercial => DashboardScreen(
          key: const ValueKey('dashboard-comercial'),
          api: widget.api,
          company: widget.company,
          user: widget.user,
        ),
        AppModule.aprobacionCartera => ApprovalsScreen(api: widget.api, company: widget.company, user: widget.user),
        AppModule.horario => ScheduleScreen(api: widget.api, company: widget.company),
        AppModule.usuarios => UsersScreen(api: widget.api, company: widget.company, user: widget.user),
        AppModule.clientes => ClientsScreen(api: widget.api, company: widget.company, user: widget.user),
        AppModule.productosEstrella => FeaturedProductsScreen(api: widget.api, company: widget.company),
        AppModule.listasPrecios => PriceListsScreen(api: widget.api, company: widget.company),
        AppModule.controlSubproductos => SubproductControlScreen(api: widget.api, company: widget.company),
        AppModule.seguimientoPedidos => OrdersScreen(
          key: const ValueKey('seguimiento-pedidos'),
          api: widget.api,
          company: widget.company,
          user: widget.user,
          tracking: true,
        ),
        AppModule.pedidos => OrdersScreen(
          key: const ValueKey('pedidos'),
          api: widget.api,
          company: widget.company,
          user: widget.user,
        ),
        AppModule.cotizaciones => QuotesScreen(api: widget.api, company: widget.company, user: widget.user),
        AppModule.cartera => PortfolioScreen(api: widget.api, company: widget.company, user: widget.user),
        AppModule.disponibilidad => AvailabilityScreen(api: widget.api, company: widget.company, user: widget.user),
        AppModule.panelControl => ManagerialScreen(api: widget.api, company: widget.company),
        AppModule.reportes => ReportsScreen(api: widget.api, company: widget.company, user: widget.user),
        AppModule.negociosNacionales => DashboardScreen(
          key: const ValueKey('negocios-nacionales'),
          api: widget.api,
          company: widget.company,
          user: widget.user,
          national: true,
        ),
      },
    );
  }
}
