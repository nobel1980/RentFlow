/// Domain models for Phase 7: Properties, Shops (Units), and Owner-Only
/// Occupancy History Timeline (`unit_occupancy_status` & `owner_unit_occupancy_history`).
///
/// Business rules (`AGENTS.md`):
/// - No unit quota or cap: an owner manages multiple properties and an
///   unrestricted number of shops/units.
/// - Every vacated shop retains all previous tenant, agreement, rent, and
///   move-out records.
/// - Money is represented in integer minor units (`*_Minor`, paisa), never `double`.
class PropertyItem {
  const PropertyItem({
    required this.id,
    required this.name,
    this.address,
    this.status = 'active',
  });

  final String id;
  final String name;
  final String? address;
  final String status;
}

class ShopUnitItem {
  const ShopUnitItem({
    required this.unitId,
    required this.propertyId,
    required this.propertyName,
    required this.unitCode,
    required this.displayName,
    required this.operationalStatus,
    required this.occupancyStatus,
    this.floorLabel,
    this.currentAgreementId,
    this.currentAgreementNumber,
    this.currentTenantId,
    this.currentTenantName,
    this.currentMonthlyRentMinor,
  });

  final String unitId;
  final String propertyId;
  final String propertyName;
  final String unitCode;
  final String displayName;
  final String? floorLabel;

  /// `'active'`, `'maintenance'`, or `'retired'`
  final String operationalStatus;

  /// Derived server-side: `'occupied'`, `'vacant'`, `'reserved'`, `'maintenance'`, `'retired'`
  final String occupancyStatus;

  final String? currentAgreementId;
  final String? currentAgreementNumber;
  final String? currentTenantId;
  final String? currentTenantName;
  final int? currentMonthlyRentMinor;

  bool get isOccupied => occupancyStatus == 'occupied';
  bool get isVacant => occupancyStatus == 'vacant';
  bool get isInMaintenance => occupancyStatus == 'maintenance';

  ShopUnitItem copyWith({
    String? displayName,
    String? floorLabel,
    String? operationalStatus,
    String? occupancyStatus,
  }) {
    return ShopUnitItem(
      unitId: unitId,
      propertyId: propertyId,
      propertyName: propertyName,
      unitCode: unitCode,
      displayName: displayName ?? this.displayName,
      floorLabel: floorLabel ?? this.floorLabel,
      operationalStatus: operationalStatus ?? this.operationalStatus,
      occupancyStatus: occupancyStatus ?? this.occupancyStatus,
      currentAgreementId: currentAgreementId,
      currentAgreementNumber: currentAgreementNumber,
      currentTenantId: currentTenantId,
      currentTenantName: currentTenantName,
      currentMonthlyRentMinor: currentMonthlyRentMinor,
    );
  }
}

class UnitOccupancyHistoryEntry {
  const UnitOccupancyHistoryEntry({
    required this.agreementUnitId,
    required this.unitId,
    required this.agreementId,
    required this.agreementNumber,
    required this.tenantId,
    required this.tenantName,
    required this.tenantPhone,
    required this.occupancyStartDate,
    required this.monthlyRentMinor,
    required this.assignmentStatus,
    this.occupancyEndDate,
    this.endedReason,
  });

  final String agreementUnitId;
  final String unitId;
  final String agreementId;
  final String agreementNumber;
  final String tenantId;
  final String tenantName;
  final String tenantPhone;
  final String occupancyStartDate;
  final String? occupancyEndDate;
  final int monthlyRentMinor;

  /// `'active'`, `'planned'`, `'ended'`, `'cancelled'`
  final String assignmentStatus;
  final String? endedReason;

  bool get isEnded => assignmentStatus == 'ended';
}
