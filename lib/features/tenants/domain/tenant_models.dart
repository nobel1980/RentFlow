/// Domain models for Phase 8: Tenant Management, Separate Financial Balances,
/// and Secure Owner-Initiated Portal Invitation / Linking.
///
/// Business rules (`AGENTS.md`):
/// - One tenant can rent multiple shops across one or multiple agreements.
/// - Tenant records survive move-out and are never hard-deleted.
/// - Security deposit, prepaid advance rent, and tenant credit are kept strictly
///   separate (`*_Minor` in integer paisa, never `double`).
class TenantItem {
  const TenantItem({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.status,
    required this.isPortalLinked,
    required this.activeShopCodes,
    required this.securityDepositMinor,
    required this.prepaidRentMinor,
    required this.tenantCreditMinor,
    this.address,
  });

  final String id;
  final String fullName;
  final String phone;
  final String? address;

  /// `'active'` or `'archived'`
  final String status;

  final bool isPortalLinked;
  final List<String> activeShopCodes;

  final int securityDepositMinor;
  final int prepaidRentMinor;
  final int tenantCreditMinor;

  bool get isActive => status == 'active';

  TenantItem copyWith({
    String? fullName,
    String? phone,
    String? address,
    String? status,
    bool? isPortalLinked,
  }) {
    return TenantItem(
      id: id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      status: status ?? this.status,
      isPortalLinked: isPortalLinked ?? this.isPortalLinked,
      activeShopCodes: activeShopCodes,
      securityDepositMinor: securityDepositMinor,
      prepaidRentMinor: prepaidRentMinor,
      tenantCreditMinor: tenantCreditMinor,
    );
  }
}

class TenantInviteResult {
  const TenantInviteResult({
    required this.inviteId,
    required this.tenantId,
    required this.inviteCode,
    required this.expiresAt,
  });

  final String inviteId;
  final String tenantId;
  final String inviteCode;
  final String expiresAt;
}
