import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/features/units/domain/unit_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository contract for Phase 7: Properties, Shops, and Owner-Only
/// Occupancy History (`unit_occupancy_status` & `owner_unit_occupancy_history`).
abstract class UnitsRepository {
  Future<List<PropertyItem>> listProperties();

  Future<List<ShopUnitItem>> listShopUnits();

  Future<List<UnitOccupancyHistoryEntry>> getUnitOccupancyHistory(
      String unitId);

  Future<ShopUnitItem> createShopUnit({
    required String propertyId,
    required String unitCode,
    required String displayName,
    String? floorLabel,
  });

  Future<ShopUnitItem> updateUnitOperationalStatus({
    required String unitId,
    required String operationalStatus,
  });
}

/// Supabase-backed implementation using the authoritative PostgreSQL views
/// `unit_occupancy_status` and `owner_unit_occupancy_history`.
class SupabaseUnitsRepository implements UnitsRepository {
  const SupabaseUnitsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<PropertyItem>> listProperties() async {
    final rows = await _client
        .from('properties')
        .select('id, name, address, status')
        .order('name');
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(
          (Map<String, dynamic> r) => PropertyItem(
            id: r['id'] as String,
            name: r['name'] as String,
            address: r['address'] as String?,
            status: (r['status'] as String?) ?? 'active',
          ),
        )
        .toList();
  }

  @override
  Future<List<ShopUnitItem>> listShopUnits() async {
    final props = await listProperties();
    final propNames = <String, String>{
      for (final PropertyItem p in props) p.id: p.name,
    };

    final statusRows =
        await _client.from('unit_occupancy_status').select().order('unit_code');
    final historyRows = await _client
        .from('owner_unit_occupancy_history')
        .select()
        .inFilter('assignment_status', <String>['active', 'planned']);

    final activeByUnit = <String, Map<String, dynamic>>{};
    for (final dynamic row in historyRows as List<dynamic>) {
      final map = row as Map<String, dynamic>;
      activeByUnit[map['unit_id'] as String] = map;
    }

    return (statusRows as List<dynamic>).cast<Map<String, dynamic>>().map((
      Map<String, dynamic> r,
    ) {
      final unitId = r['unit_id'] as String;
      final propId = r['property_id'] as String;
      final active = activeByUnit[unitId];
      return ShopUnitItem(
        unitId: unitId,
        propertyId: propId,
        propertyName: propNames[propId] ?? '',
        unitCode: r['unit_code'] as String,
        displayName: r['display_name'] as String,
        operationalStatus: r['operational_status'] as String,
        occupancyStatus: r['occupancy_status'] as String,
        currentAgreementId: r['current_agreement_id'] as String?,
        currentAgreementNumber: active?['agreement_number'] as String?,
        currentTenantId: r['current_tenant_id'] as String?,
        currentTenantName: active?['tenant_name'] as String?,
        currentMonthlyRentMinor:
            (active?['monthly_rent_minor'] as num?)?.toInt(),
      );
    }).toList();
  }

  @override
  Future<List<UnitOccupancyHistoryEntry>> getUnitOccupancyHistory(
    String unitId,
  ) async {
    final rows = await _client
        .from('owner_unit_occupancy_history')
        .select()
        .eq('unit_id', unitId)
        .order('occupancy_start_date', ascending: false);

    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(
          (Map<String, dynamic> r) => UnitOccupancyHistoryEntry(
            agreementUnitId: r['agreement_unit_id'] as String,
            unitId: r['unit_id'] as String,
            agreementId: r['agreement_id'] as String,
            agreementNumber: r['agreement_number'] as String,
            tenantId: r['tenant_id'] as String,
            tenantName: r['tenant_name'] as String,
            tenantPhone: (r['tenant_phone'] as String?) ?? '',
            occupancyStartDate: r['occupancy_start_date'].toString(),
            occupancyEndDate: r['occupancy_end_date']?.toString(),
            monthlyRentMinor: (r['monthly_rent_minor'] as num).toInt(),
            assignmentStatus: r['assignment_status'] as String,
            endedReason: r['ended_reason'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<ShopUnitItem> createShopUnit({
    required String propertyId,
    required String unitCode,
    required String displayName,
    String? floorLabel,
  }) async {
    await _client.from('units').insert(<String, dynamic>{
      'property_id': propertyId,
      'unit_code': unitCode.trim(),
      'display_name': displayName.trim(),
      'floor_label': (floorLabel == null || floorLabel.trim().isEmpty)
          ? null
          : floorLabel.trim(),
    });
    final all = await listShopUnits();
    return all.firstWhere(
      (ShopUnitItem u) =>
          u.propertyId == propertyId && u.unitCode == unitCode.trim(),
    );
  }

  @override
  Future<ShopUnitItem> updateUnitOperationalStatus({
    required String unitId,
    required String operationalStatus,
  }) async {
    await _client
        .from('units')
        .update(<String, dynamic>{'operational_status': operationalStatus}).eq(
            'id', unitId);
    final all = await listShopUnits();
    return all.firstWhere((ShopUnitItem u) => u.unitId == unitId);
  }
}

/// Seeded in-memory repository used when running local previews and widget
/// tests without a live Supabase connection. Pre-seeded with >10 units across
/// properties (proving no unit cap) and a re-let shop (`S-01`) with both a
/// previous ended tenant and a current active tenant in its occupancy history.
class InMemoryUnitsRepository implements UnitsRepository {
  InMemoryUnitsRepository() {
    _properties.addAll(const <PropertyItem>[
      PropertyItem(
        id: 'prop-1',
        name: 'Akand Super Market',
        address: 'Station Road, Bogura',
      ),
      PropertyItem(
        id: 'prop-2',
        name: 'City Plaza Annex',
        address: 'New Market Road, Dhaka',
      ),
    ]);

    _units.addAll(<ShopUnitItem>[
      const ShopUnitItem(
        unitId: 'unit-s01',
        propertyId: 'prop-1',
        propertyName: 'Akand Super Market',
        unitCode: 'S-01',
        displayName: 'Corner Pharmacy Shop',
        floorLabel: 'Ground Floor',
        operationalStatus: 'active',
        occupancyStatus: 'occupied',
        currentAgreementId: 'agr-2026-04',
        currentAgreementNumber: 'AG-2026-04',
        currentTenantId: 'ten-karim',
        currentTenantName: 'Karim Traders',
        currentMonthlyRentMinor: 2600000,
      ),
      const ShopUnitItem(
        unitId: 'unit-s02',
        propertyId: 'prop-1',
        propertyName: 'Akand Super Market',
        unitCode: 'S-02',
        displayName: 'Textile & Garments',
        floorLabel: 'Ground Floor',
        operationalStatus: 'active',
        occupancyStatus: 'vacant',
      ),
      const ShopUnitItem(
        unitId: 'unit-s03',
        propertyId: 'prop-1',
        propertyName: 'Akand Super Market',
        unitCode: 'S-03',
        displayName: 'Electronics Showroom',
        floorLabel: '1st Floor',
        operationalStatus: 'maintenance',
        occupancyStatus: 'maintenance',
      ),
      for (int i = 4; i <= 12; i++)
        ShopUnitItem(
          unitId: 'unit-s${i.toString().padLeft(2, '0')}',
          propertyId: i <= 8 ? 'prop-1' : 'prop-2',
          propertyName: i <= 8 ? 'Akand Super Market' : 'City Plaza Annex',
          unitCode: 'S-${i.toString().padLeft(2, '0')}',
          displayName: 'Retail Unit $i',
          floorLabel: i <= 8 ? '1st Floor' : '2nd Floor',
          operationalStatus: 'active',
          occupancyStatus: i.isEven ? 'occupied' : 'vacant',
          currentAgreementId: i.isEven ? 'agr-bulk-$i' : null,
          currentAgreementNumber: i.isEven ? 'AG-10$i' : null,
          currentTenantId: i.isEven ? 'ten-rahim' : null,
          currentTenantName: i.isEven ? 'Rahim Enterprise' : null,
          currentMonthlyRentMinor: i.isEven ? 1500000 : null,
        ),
    ]);

    _historyByUnit['unit-s01'] = <UnitOccupancyHistoryEntry>[
      const UnitOccupancyHistoryEntry(
        agreementUnitId: 'au-s01-current',
        unitId: 'unit-s01',
        agreementId: 'agr-2026-04',
        agreementNumber: 'AG-2026-04',
        tenantId: 'ten-karim',
        tenantName: 'Karim Traders',
        tenantPhone: '01711-223344',
        occupancyStartDate: '2026-04-01',
        monthlyRentMinor: 2600000,
        assignmentStatus: 'active',
      ),
      const UnitOccupancyHistoryEntry(
        agreementUnitId: 'au-s01-prior',
        unitId: 'unit-s01',
        agreementId: 'agr-2025-01',
        agreementNumber: 'AG-2025-01',
        tenantId: 'ten-rahim',
        tenantName: 'Rahim Enterprise',
        tenantPhone: '01819-556677',
        occupancyStartDate: '2025-01-01',
        occupancyEndDate: '2026-03-31',
        monthlyRentMinor: 2000000,
        assignmentStatus: 'ended',
        endedReason:
            'Non-renewal completed at expiry; keys & settlement finalized',
      ),
    ];

    _historyByUnit['unit-s02'] = <UnitOccupancyHistoryEntry>[
      const UnitOccupancyHistoryEntry(
        agreementUnitId: 'au-s02-prior',
        unitId: 'unit-s02',
        agreementId: 'agr-2024-09',
        agreementNumber: 'AG-2024-09',
        tenantId: 'ten-salma',
        tenantName: 'Salma Boutique',
        tenantPhone: '01912-889900',
        occupancyStartDate: '2024-09-01',
        occupancyEndDate: '2026-08-31',
        monthlyRentMinor: 1800000,
        assignmentStatus: 'ended',
        endedReason: 'Mutual move-out completed; full deposit settled',
      ),
    ];
  }

  final List<PropertyItem> _properties = <PropertyItem>[];
  final List<ShopUnitItem> _units = <ShopUnitItem>[];
  final Map<String, List<UnitOccupancyHistoryEntry>> _historyByUnit =
      <String, List<UnitOccupancyHistoryEntry>>{};

  @override
  Future<List<PropertyItem>> listProperties() async =>
      List<PropertyItem>.unmodifiable(_properties);

  @override
  Future<List<ShopUnitItem>> listShopUnits() async =>
      List<ShopUnitItem>.unmodifiable(_units);

  @override
  Future<List<UnitOccupancyHistoryEntry>> getUnitOccupancyHistory(
    String unitId,
  ) async {
    return List<UnitOccupancyHistoryEntry>.unmodifiable(
      _historyByUnit[unitId] ?? const <UnitOccupancyHistoryEntry>[],
    );
  }

  @override
  Future<ShopUnitItem> createShopUnit({
    required String propertyId,
    required String unitCode,
    required String displayName,
    String? floorLabel,
  }) async {
    final code = unitCode.trim();
    final name = displayName.trim();
    if (code.isEmpty || name.isEmpty) {
      throw ArgumentError('VALIDATION_ERROR');
    }
    final duplicate = _units.any(
      (ShopUnitItem u) =>
          u.propertyId == propertyId &&
          u.unitCode.toLowerCase() == code.toLowerCase(),
    );
    if (duplicate) {
      throw StateError('VALIDATION_ERROR');
    }
    final prop = _properties.firstWhere(
      (PropertyItem p) => p.id == propertyId,
      orElse: () => _properties.first,
    );
    final created = ShopUnitItem(
      unitId: 'unit-${_units.length + 1}',
      propertyId: prop.id,
      propertyName: prop.name,
      unitCode: code,
      displayName: name,
      floorLabel: (floorLabel == null || floorLabel.trim().isEmpty)
          ? null
          : floorLabel.trim(),
      operationalStatus: 'active',
      occupancyStatus: 'vacant',
    );
    _units.insert(0, created);
    return created;
  }

  @override
  Future<ShopUnitItem> updateUnitOperationalStatus({
    required String unitId,
    required String operationalStatus,
  }) async {
    final index = _units.indexWhere((ShopUnitItem u) => u.unitId == unitId);
    if (index < 0) {
      throw StateError('VALIDATION_ERROR');
    }
    final existing = _units[index];
    final nextOccupancy = operationalStatus == 'active'
        ? (existing.currentAgreementId != null ? 'occupied' : 'vacant')
        : operationalStatus;
    final updated = existing.copyWith(
      operationalStatus: operationalStatus,
      occupancyStatus: nextOccupancy,
    );
    _units[index] = updated;
    return updated;
  }
}

final unitsRepositoryProvider = Provider<UnitsRepository>((Ref ref) {
  return InMemoryUnitsRepository();
});

class UnitsFilterState {
  const UnitsFilterState({
    this.searchQuery = '',
    this.statusFilter = 'all',
  });

  final String searchQuery;
  final String statusFilter;

  UnitsFilterState copyWith({
    String? searchQuery,
    String? statusFilter,
  }) {
    return UnitsFilterState(
      searchQuery: searchQuery ?? this.searchQuery,
      statusFilter: statusFilter ?? this.statusFilter,
    );
  }
}

class UnitsFilterNotifier extends Notifier<UnitsFilterState> {
  @override
  UnitsFilterState build() => const UnitsFilterState();

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setStatusFilter(String filter) {
    state = state.copyWith(statusFilter: filter);
  }
}

final unitsFilterProvider =
    NotifierProvider<UnitsFilterNotifier, UnitsFilterState>(
  UnitsFilterNotifier.new,
);

class ShopUnitsController extends AsyncNotifier<List<ShopUnitItem>> {
  @override
  Future<List<ShopUnitItem>> build() async {
    return ref.watch(unitsRepositoryProvider).listShopUnits();
  }

  Future<void> addShop({
    required String propertyId,
    required String unitCode,
    required String displayName,
    String? floorLabel,
  }) async {
    final repo = ref.read(unitsRepositoryProvider);
    await repo.createShopUnit(
      propertyId: propertyId,
      unitCode: unitCode,
      displayName: displayName,
      floorLabel: floorLabel,
    );
    state = AsyncData<List<ShopUnitItem>>(await repo.listShopUnits());
  }

  Future<void> setOperationalStatus({
    required String unitId,
    required String operationalStatus,
  }) async {
    final repo = ref.read(unitsRepositoryProvider);
    await repo.updateUnitOperationalStatus(
      unitId: unitId,
      operationalStatus: operationalStatus,
    );
    state = AsyncData<List<ShopUnitItem>>(await repo.listShopUnits());
  }
}

final shopUnitsControllerProvider =
    AsyncNotifierProvider<ShopUnitsController, List<ShopUnitItem>>(
  ShopUnitsController.new,
);

final unitOccupancyHistoryProvider =
    FutureProvider.family<List<UnitOccupancyHistoryEntry>, String>(
        (Ref ref, String unitId) async {
  return ref.watch(unitsRepositoryProvider).getUnitOccupancyHistory(unitId);
});
