import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/core/locale/locale_controller.dart';
import 'package:rentflow/core/money/money_formatter.dart';
import 'package:rentflow/core/widgets/async_state_view.dart';
import 'package:rentflow/core/widgets/status_badge.dart';
import 'package:rentflow/features/units/data/units_repository.dart';
import 'package:rentflow/features/units/domain/unit_models.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

/// Phase 7 Owner Shops & Occupancy History screen.
///
/// Enforces:
/// - Unrestricted number of shops/properties (zero quota UI or checks).
/// - Search and status filtering (`all`, `occupied`, `vacant`, `maintenance`).
/// - Owner-only Occupancy History Timeline showing all previous (`ended`) and
///   current (`active`) tenant occupancies when a shop is opened.
class UnitsScreen extends ConsumerWidget {
  const UnitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(unitsFilterProvider);
    final unitsAsync = ref.watch(shopUnitsControllerProvider);
    final localeCode = AppLocales.toDatabaseCode(
      ref.watch(localeControllerProvider),
    );

    final allUnits = unitsAsync.valueOrNull ?? const <ShopUnitItem>[];
    final filtered = allUnits.where((ShopUnitItem unit) {
      if (filter.statusFilter != 'all' &&
          unit.occupancyStatus != filter.statusFilter) {
        return false;
      }
      final q = filter.searchQuery.trim().toLowerCase();
      if (q.isEmpty) {
        return true;
      }
      return unit.unitCode.toLowerCase().contains(q) ||
          unit.displayName.toLowerCase().contains(q) ||
          unit.propertyName.toLowerCase().contains(q) ||
          (unit.currentTenantName?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                key: const Key('shops_search_field'),
                onChanged: (String value) => ref
                    .read(unitsFilterProvider.notifier)
                    .setSearchQuery(value),
                decoration: InputDecoration(
                  hintText: l10n.shopsSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('add_shop_button'),
                onPressed: () => _showAddShopDialog(context, ref),
                icon: const Icon(Icons.add_business_outlined),
                label: Text(l10n.addShopAction),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: <Widget>[
              _FilterChipButton(
                chipKey: const Key('shop_filter_all'),
                label: '${l10n.filterAll} (${allUnits.length})',
                selected: filter.statusFilter == 'all',
                onTap: () => ref
                    .read(unitsFilterProvider.notifier)
                    .setStatusFilter('all'),
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                chipKey: const Key('shop_filter_occupied'),
                label: l10n.statusOccupied,
                selected: filter.statusFilter == 'occupied',
                onTap: () => ref
                    .read(unitsFilterProvider.notifier)
                    .setStatusFilter('occupied'),
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                chipKey: const Key('shop_filter_vacant'),
                label: l10n.statusVacant,
                selected: filter.statusFilter == 'vacant',
                onTap: () => ref
                    .read(unitsFilterProvider.notifier)
                    .setStatusFilter('vacant'),
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                chipKey: const Key('shop_filter_maintenance'),
                label: l10n.statusMaintenance,
                selected: filter.statusFilter == 'maintenance',
                onTap: () => ref
                    .read(unitsFilterProvider.notifier)
                    .setStatusFilter('maintenance'),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncStateView(
            isLoading: unitsAsync.isLoading,
            isEmpty: filtered.isEmpty,
            errorMessage: unitsAsync.hasError ? l10n.errorGeneric : null,
            onRetry: () => ref.invalidate(shopUnitsControllerProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) {
                final unit = filtered[index];
                return _ShopUnitCard(
                  unit: unit,
                  localeCode: localeCode,
                  onTap: () => _showShopDetailSheet(context, unit),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddShopDialog(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final floorController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(l10n.addShopAction),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  key: const Key('new_shop_code_field'),
                  controller: codeController,
                  decoration: InputDecoration(labelText: l10n.shopCodeLabel),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('new_shop_name_field'),
                  controller: nameController,
                  decoration: InputDecoration(labelText: l10n.shopNameLabel),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('new_shop_floor_field'),
                  controller: floorController,
                  decoration: InputDecoration(labelText: l10n.shopFloorLabel),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              key: const Key('save_new_shop_button'),
              onPressed: () async {
                if (codeController.text.trim().isEmpty ||
                    nameController.text.trim().isEmpty) {
                  return;
                }
                await ref.read(shopUnitsControllerProvider.notifier).addShop(
                      propertyId: 'prop-1',
                      unitCode: codeController.text,
                      displayName: nameController.text,
                      floorLabel: floorController.text,
                    );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text(l10n.saveAction),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showShopDetailSheet(
    BuildContext context,
    ShopUnitItem unit,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (BuildContext context, ScrollController scrollController) {
            return ShopDetailSheet(
              unit: unit,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.chipKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key chipKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: FilterChip(
        key: chipKey,
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _ShopUnitCard extends StatelessWidget {
  const _ShopUnitCard({
    required this.unit,
    required this.localeCode,
    required this.onTap,
  });

  final ShopUnitItem unit;
  final String localeCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: Key('shop_card_${unit.unitCode}'),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                    '${unit.unitCode} · ${unit.displayName}',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  StatusBadge(status: _mapSemanticStatus(unit.occupancyStatus)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                unit.floorLabel != null
                    ? '${unit.propertyName} · ${unit.floorLabel}'
                    : unit.propertyName,
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              if (unit.currentTenantName != null &&
                  unit.currentMonthlyRentMinor != null)
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: <Widget>[
                    Text(
                      '${l10n.currentTenantLabel}: ${unit.currentTenantName}',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${l10n.currentRentLabel}: ${MoneyFormatter.formatMinor(unit.currentMonthlyRentMinor!, locale: localeCode)}',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  l10n.noActiveTenantLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static SemanticStatus _mapSemanticStatus(String occupancyStatus) {
    switch (occupancyStatus) {
      case 'occupied':
        return SemanticStatus.occupied;
      case 'maintenance':
        return SemanticStatus.maintenance;
      default:
        return SemanticStatus.vacant;
    }
  }
}

/// Shop detail modal displaying current occupancy and the Owner-Only
/// Occupancy History Timeline (`owner_unit_occupancy_history`).
class ShopDetailSheet extends ConsumerWidget {
  const ShopDetailSheet({
    required this.unit,
    required this.scrollController,
    super.key,
  });

  final ShopUnitItem unit;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final historyAsync = ref.watch(unitOccupancyHistoryProvider(unit.unitId));
    final localeCode = AppLocales.toDatabaseCode(
      ref.watch(localeControllerProvider),
    );
    final textTheme = Theme.of(context).textTheme;
    final history =
        historyAsync.valueOrNull ?? const <UnitOccupancyHistoryEntry>[];

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              '${unit.unitCode} · ${unit.displayName}',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            StatusBadge(
              status: _ShopUnitCard._mapSemanticStatus(unit.occupancyStatus),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(unit.propertyName, style: textTheme.bodyMedium),
        const SizedBox(height: 14),
        if (!unit.isOccupied)
          OutlinedButton.icon(
            key: const Key('toggle_unit_maintenance_button'),
            onPressed: () async {
              final nextStatus = unit.operationalStatus == 'maintenance'
                  ? 'active'
                  : 'maintenance';
              await ref
                  .read(shopUnitsControllerProvider.notifier)
                  .setOperationalStatus(
                    unitId: unit.unitId,
                    operationalStatus: nextStatus,
                  );
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.build_circle_outlined),
            label: Text(
              unit.operationalStatus == 'maintenance'
                  ? l10n.setActiveUnitAction
                  : l10n.setMaintenanceAction,
            ),
          ),
        const SizedBox(height: 16),
        Text(
          l10n.occupancyHistoryTitle,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.occupancyHistorySubtitle,
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (historyAsync.isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (history.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.emptyStateTitle),
            ),
          )
        else
          ...history.map(
            (UnitOccupancyHistoryEntry entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                key: Key('occupancy_history_${entry.agreementUnitId}'),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
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
                            '${entry.tenantName} (${entry.agreementNumber})',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          StatusBadge(
                            status: entry.isEnded
                                ? SemanticStatus.vacant
                                : SemanticStatus.occupied,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.isEnded
                            ? '${l10n.historyStatusEnded}: ${entry.occupancyStartDate} → ${entry.occupancyEndDate}'
                            : '${l10n.historyStatusActive}: ${entry.occupancyStartDate}',
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${l10n.currentRentLabel}: ${MoneyFormatter.formatMinor(entry.monthlyRentMinor, locale: localeCode)}',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (entry.endedReason != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          entry.endedReason!,
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
