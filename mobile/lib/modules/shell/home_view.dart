import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/connectivity/connectivity_service.dart';
import '../../core/session/session_service.dart';
import '../../routes/app_routes.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_view.dart';
import '../dashboard/dashboard_view.dart';
import '../forecasting/forecasting_views.dart';
import '../imports/imports_view.dart';
import '../inventory/inventory_view.dart';
import '../movements/movements_view.dart';

class HomeController extends GetxController {
  final RxInt tab = 0.obs;
}

class AppSection {
  const AppSection(this.label, this.icon, this.selectedIcon, this.builder,
      {this.group, this.showRecordMovement = false});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;

  /// Header shown above the first section of a group in the drawer.
  final String? group;
  final bool showRecordMovement;
}

final List<AppSection> appSections = [
  AppSection('Dashboard', Icons.dashboard_outlined, Icons.dashboard,
      () => const DashboardView()),
  AppSection('Inventory', Icons.inventory_2_outlined, Icons.inventory_2,
      () => const InventoryView(),
      group: 'Operations', showRecordMovement: true),
  AppSection('Movements', Icons.swap_vert, Icons.swap_vert_circle,
      () => const MovementsView(), showRecordMovement: true),
  AppSection('Catalogue', Icons.category_outlined, Icons.category,
      () => const CatalogView()),
  AppSection('Imports', Icons.upload_file_outlined, Icons.upload_file,
      () => const ImportsView()),
  AppSection('Forecasts', Icons.auto_graph_outlined, Icons.auto_graph,
      () => const ForecastView(),
      group: 'Planning'),
  AppSection('Model evaluation', Icons.fact_check_outlined, Icons.fact_check,
      () => const EvaluationView()),
];

int sectionIndex(String label) => appSections.indexWhere((s) => s.label == label);

/// Responsive shell: a permanent navigation panel on wide screens and a
/// slide-out drawer on phones.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  static const _wideBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeController>();
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= _wideBreakpoint;
      return Obx(() {
        final index = home.tab.value.clamp(0, appSections.length - 1);
        final section = appSections[index];
        final nav = _NavPanel(
          selected: index,
          onSelected: (i) {
            home.tab.value = i;
            if (!wide) Navigator.of(context).maybePop();
          },
        );
        final body = KeyedSubtree(key: ValueKey(index), child: section.builder());
        return Scaffold(
          appBar: AppBar(
            title: Text(section.label),
            automaticallyImplyLeading: !wide,
            actions: const [_OfflineIndicator(), _UserMenu()],
          ),
          drawer: wide ? null : nav,
          floatingActionButton: section.showRecordMovement
              ? RoleGate(
                  child: FloatingActionButton.extended(
                    key: const Key('home-record-movement'),
                    icon: const Icon(Icons.swap_vert),
                    label: const Text('Record movement'),
                    onPressed: () => Get.toNamed<bool>(Routes.movementForm),
                  ),
                )
              : null,
          body: wide
              ? Row(
                  children: [
                    SizedBox(width: 260, child: nav),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
        );
      });
    });
  }
}

class _NavPanel extends StatelessWidget {
  const _NavPanel({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NavigationDrawer(
      key: const Key('nav-panel'),
      selectedIndex: selected,
      onDestinationSelected: onSelected,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 16, 12),
          child: Row(children: [
            Icon(Icons.inventory_2_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('SmartStock AI', style: theme.textTheme.titleMedium),
          ]),
        ),
        for (final s in appSections) ...[
          if (s.group != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
              child: Text(s.group!, style: theme.textTheme.labelMedium),
            ),
          NavigationDrawerDestination(
            icon: Icon(s.icon),
            selectedIcon: Icon(s.selectedIcon),
            label: Text(s.label),
          ),
        ],
      ],
    );
  }
}

class _OfflineIndicator extends StatelessWidget {
  const _OfflineIndicator();

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<ConnectivityService>()) return const SizedBox.shrink();
    final connectivity = Get.find<ConnectivityService>();
    return Obx(() => connectivity.isOnline.value
        ? const SizedBox.shrink()
        : const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Tooltip(
              message: 'No network connection',
              child: Icon(Icons.cloud_off),
            ),
          ));
  }
}

class _UserMenu extends StatelessWidget {
  const _UserMenu();

  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionService>();
    return Obx(() {
      final user = session.user.value;
      return PopupMenuButton<String>(
        tooltip: 'Account',
        icon: const Icon(Icons.account_circle_outlined),
        onSelected: (value) async {
          if (value == 'logout') {
            await session.logout();
            Get.offAllNamed(Routes.login);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            enabled: false,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(user?.displayName ?? ''),
              subtitle: Text('${user?.email ?? ''}\nRole: ${user?.role.label ?? ''}'),
              isThreeLine: true,
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'logout',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout),
              title: Text('Sign out'),
            ),
          ),
        ],
      );
    });
  }
}
