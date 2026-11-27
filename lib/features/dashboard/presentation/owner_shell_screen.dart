import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rentflow/core/locale/locale_controller.dart';
import 'package:rentflow/core/money/money_formatter.dart';
import 'package:rentflow/core/widgets/separate_fund_cards.dart';
import 'package:rentflow/core/widgets/status_badge.dart';
import 'package:rentflow/features/notifications/presentation/notifications_inbox_sheet.dart';
import 'package:rentflow/features/payments/presentation/payments_screen.dart';
import 'package:rentflow/features/reports/presentation/reports_screen.dart';
import 'package:rentflow/features/tenants/presentation/tenants_screen.dart';
import 'package:rentflow/features/units/presentation/units_screen.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

/// Owner Dashboard and navigation shell (`RentFlow_Master_Blueprint.md` §13.3).
///
/// Displays authoritative server-side summary metrics without any unit quota
/// or combined advance balance.
class OwnerShellScreen extends ConsumerStatefulWidget {
  const OwnerShellScreen({
    this.expectedRentMinor = 1800000,
    this.allocatedSettledMinor = 1300000,
    this.outstandingRentMinor = 500000,
    this.overdueRentMinor = 200000,
    this.totalUnits = 15,
    this.occupiedUnits = 12,
    this.vacantUnits = 3,
    this.securityDepositHeldMinor = 5000000,
    this.prepaidRentHeldMinor = 800000,
    this.tenantCreditHeldMinor = 150000,
    super.key,
  });

  final int expectedRentMinor;
  final int allocatedSettledMinor;
  final int outstandingRentMinor;
  final int overdueRentMinor;
  final int totalUnits;
  final int occupiedUnits;
  final int vacantUnits;
  final int securityDepositHeldMinor;
  final int prepaidRentHeldMinor;
  final int tenantCreditHeldMinor;

  @override
  ConsumerState<OwnerShellScreen> createState() => _OwnerShellScreenState();
}

class _OwnerShellScreenState extends ConsumerState<OwnerShellScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    final localeCode = AppLocales.toDatabaseCode(locale);

    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.appTitle} · ${l10n.roleOwner}'),
        actions: <Widget>[
          IconButton(
            key: const Key('owner_notifications_button'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => _showNotificationsSheet(context),
            icon: const Icon(Icons.notifications_outlined),
          ),
          IconButton(
            key: const Key('owner_locale_toggle_button'),
            tooltip: l10n.languageLabel,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () =>
                ref.read(localeControllerProvider.notifier).toggleLocale(),
            icon: const Icon(Icons.translate_outlined),
          ),
          IconButton(
            key: const Key('switch_to_tenant_portal_button'),
            tooltip: l10n.switchRolePreview,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => context.go('/tenant'),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: _buildSelectedBody(context, l10n, localeCode),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int idx) {
          setState(() {
            _selectedIndex = idx;
          });
        },
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            label: l10n.navDashboard,
          ),
          NavigationDestination(
            icon: const Icon(Icons.storefront_outlined),
            label: l10n.navShops,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            label: l10n.navTenants,
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            label: l10n.navPayments,
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            label: l10n.navReports,
          ),
        ],
      ),
    );
  }

  Future<void> _showNotificationsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          minChildSize: 0.45,
          builder: (BuildContext context, ScrollController scrollController) {
            return NotificationsInboxSheet(scrollController: scrollController);
          },
        );
      },
    );
  }

  Widget _buildSelectedBody(
    BuildContext context,
    AppLocalizations l10n,
    String localeCode,
  ) {
    if (_selectedIndex == 1) {
      return const UnitsScreen();
    }
    if (_selectedIndex == 2) {
      return const TenantsScreen();
    }
    if (_selectedIndex == 3) {
      return const PaymentsScreen();
    }
    if (_selectedIndex == 4) {
      return const ReportsScreen();
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildBillingCard(context, l10n, localeCode),
        const SizedBox(height: 16),
        _buildOccupancyCard(context, l10n),
        const SizedBox(height: 16),
        SeparateFundCards(
          securityDepositMinor: widget.securityDepositHeldMinor,
          prepaidRentMinor: widget.prepaidRentHeldMinor,
          tenantCreditMinor: widget.tenantCreditHeldMinor,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('owner_record_payment_button'),
          onPressed: () {
            setState(() {
              _selectedIndex = 3;
            });
          },
          icon: const Icon(Icons.payments_outlined),
          label: Text(l10n.recordPaymentAction),
        ),
      ],
    );
  }

  Widget _buildBillingCard(
    BuildContext context,
    AppLocalizations l10n,
    String localeCode,
  ) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  l10n.billingOverviewTitle,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                StatusBadge(
                  status: widget.overdueRentMinor > 0
                      ? SemanticStatus.overdue
                      : SemanticStatus.paid,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MetricRow(
              label: l10n.expectedRentLabel,
              value: MoneyFormatter.formatMinor(
                widget.expectedRentMinor,
                locale: localeCode,
              ),
            ),
            const Divider(height: 16),
            _MetricRow(
              label: l10n.collectedAllocatedLabel,
              value: MoneyFormatter.formatMinor(
                widget.allocatedSettledMinor,
                locale: localeCode,
              ),
            ),
            const Divider(height: 16),
            _MetricRow(
              label: l10n.outstandingRentLabel,
              value: MoneyFormatter.formatMinor(
                widget.outstandingRentMinor,
                locale: localeCode,
              ),
            ),
            const Divider(height: 16),
            _MetricRow(
              label: l10n.overdueRentLabel,
              value: MoneyFormatter.formatMinor(
                widget.overdueRentMinor,
                locale: localeCode,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOccupancyCard(BuildContext context, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.occupancyOverviewTitle,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _CountChip(
                  label: l10n.totalUnitsLabel,
                  count: widget.totalUnits,
                ),
                _CountChip(
                  label: l10n.occupiedUnitsLabel,
                  count: widget.occupiedUnits,
                ),
                _CountChip(
                  label: l10n.vacantUnitsLabel,
                  count: widget.vacantUnits,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: $count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
