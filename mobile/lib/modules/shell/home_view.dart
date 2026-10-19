import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/connectivity/connectivity_service.dart';
import '../../core/session/session_service.dart';
import '../../routes/app_routes.dart';
import '../../widgets/common.dart';
import '../catalog/catalog_view.dart';
import '../dashboard/dashboard_view.dart';
import '../inventory/inventory_view.dart';
import '../movements/movements_view.dart';

class HomeController extends GetxController {
  final RxInt tab = 0.obs;
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Dashboard', Icons.dashboard_outlined, Icons.dashboard),
  _Destination('Inventory', Icons.inventory_2_outlined, Icons.inventory_2),
  _Destination('Movements', Icons.swap_vert, Icons.swap_vert_circle),
  _Destination('Catalogue', Icons.category_outlined, Icons.category),
];

/// Responsive app shell: bottom navigation on phones, a rail on wider screens.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  Widget _page(int index) {
    switch (index) {
      case 0:
        return const DashboardView();
      case 1:
        return const InventoryView();
      case 2:
        return const MovementsView();
      default:
        return const CatalogView();
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeController>();
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 600;
      return Obx(() {
        final index = home.tab.value;
        final body = KeyedSubtree(key: ValueKey(index), child: _page(index));
        return Scaffold(
          appBar: AppBar(
            title: Text(_destinations[index].label),
            actions: const [_OfflineIndicator(), _UserMenu()],
          ),
          floatingActionButton: (index == 1 || index == 2)
              ? RoleGate(
                  child: FloatingActionButton.extended(
                    key: const Key('home-record-movement'),
                    icon: const Icon(Icons.swap_vert),
                    label: const Text('Record movement'),
                    onPressed: () => Get.toNamed<bool>(Routes.movementForm),
                  ),
                )
              : null,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: (i) => home.tab.value = i,
                  destinations: [
                    for (final d in _destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: d.label,
                      ),
                  ],
                ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: index,
                      onDestinationSelected: (i) => home.tab.value = i,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final d in _destinations)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ),
                      ],
                    ),
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
