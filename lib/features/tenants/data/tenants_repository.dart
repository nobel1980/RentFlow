import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/features/tenants/domain/tenant_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository contract for Phase 8: Tenant Management and Secure Portal Linking
/// (`owner_create_tenant_invite`, `tenant_claim_invite`, `owner_revoke_tenant_access`).
abstract class TenantsRepository {
  Future<List<TenantItem>> listTenants();

  Future<TenantItem> createTenant({
    required String fullName,
    required String phone,
    String? address,
  });

  Future<TenantItem> archiveTenant(String tenantId);

  Future<TenantInviteResult> createTenantInvite({
    required String tenantId,
    int expiresInHours = 168,
  });

  Future<void> revokeTenantPortalAccess({
    required String tenantId,
    required String reason,
  });

  Future<String> claimTenantInvite(String inviteCode);
}

class SupabaseTenantsRepository implements TenantsRepository {
  const SupabaseTenantsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<TenantItem>> listTenants() async {
    final rows = await _client
        .from('tenants')
        .select('id, full_name, phone, address, status')
        .order('full_name');
    final links = await _client
        .from('tenant_profile_links')
        .select('tenant_id, verified_at, revoked_at');
    final depRows = await _client
        .from('security_deposit_balances')
        .select('tenant_id, balance_minor');
    final preRows = await _client
        .from('prepaid_rent_balances')
        .select('tenant_id, balance_minor');
    final creRows = await _client
        .from('tenant_credit_balances')
        .select('tenant_id, balance_minor');

    final linkedTenants = <String>{
      for (final dynamic l in links as List<dynamic>)
        if ((l as Map<String, dynamic>)['verified_at'] != null &&
            l['revoked_at'] == null)
          l['tenant_id'] as String,
    };

    final depByTenant = <String, int>{};
    for (final dynamic r in depRows as List<dynamic>) {
      final map = r as Map<String, dynamic>;
      final tid = map['tenant_id'] as String;
      depByTenant[tid] =
          (depByTenant[tid] ?? 0) + (map['balance_minor'] as num).toInt();
    }

    final preByTenant = <String, int>{
      for (final dynamic r in preRows as List<dynamic>)
        (r as Map<String, dynamic>)['tenant_id'] as String:
            (r['balance_minor'] as num).toInt(),
    };

    final creByTenant = <String, int>{
      for (final dynamic r in creRows as List<dynamic>)
        (r as Map<String, dynamic>)['tenant_id'] as String:
            (r['balance_minor'] as num).toInt(),
    };

    return (rows as List<dynamic>).cast<Map<String, dynamic>>().map((
      Map<String, dynamic> r,
    ) {
      final tid = r['id'] as String;
      return TenantItem(
        id: tid,
        fullName: r['full_name'] as String,
        phone: r['phone'] as String,
        address: r['address'] as String?,
        status: (r['status'] as String?) ?? 'active',
        isPortalLinked: linkedTenants.contains(tid),
        activeShopCodes: const <String>[],
        securityDepositMinor: depByTenant[tid] ?? 0,
        prepaidRentMinor: preByTenant[tid] ?? 0,
        tenantCreditMinor: creByTenant[tid] ?? 0,
      );
    }).toList();
  }

  @override
  Future<TenantItem> createTenant({
    required String fullName,
    required String phone,
    String? address,
  }) async {
    final row = await _client
        .from('tenants')
        .insert(<String, dynamic>{
          'full_name': fullName.trim(),
          'phone': phone.trim(),
          'address': (address == null || address.trim().isEmpty)
              ? null
              : address.trim(),
        })
        .select('id, full_name, phone, address, status')
        .single();
    return TenantItem(
      id: row['id'] as String,
      fullName: row['full_name'] as String,
      phone: row['phone'] as String,
      address: row['address'] as String?,
      status: (row['status'] as String?) ?? 'active',
      isPortalLinked: false,
      activeShopCodes: const <String>[],
      securityDepositMinor: 0,
      prepaidRentMinor: 0,
      tenantCreditMinor: 0,
    );
  }

  @override
  Future<TenantItem> archiveTenant(String tenantId) async {
    await _client
        .from('tenants')
        .update(<String, dynamic>{'status': 'archived'}).eq('id', tenantId);
    final all = await listTenants();
    return all.firstWhere((TenantItem t) => t.id == tenantId);
  }

  @override
  Future<TenantInviteResult> createTenantInvite({
    required String tenantId,
    int expiresInHours = 168,
  }) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'owner_create_tenant_invite',
      params: <String, dynamic>{
        'p_tenant_id': tenantId,
        'p_expires_in_hours': expiresInHours,
      },
    );
    return TenantInviteResult(
      inviteId: res['invite_id'] as String,
      tenantId: res['tenant_id'] as String,
      inviteCode: res['invite_code'] as String,
      expiresAt: res['expires_at'].toString(),
    );
  }

  @override
  Future<void> revokeTenantPortalAccess({
    required String tenantId,
    required String reason,
  }) async {
    await _client.rpc<Map<String, dynamic>>(
      'owner_revoke_tenant_access',
      params: <String, dynamic>{
        'p_tenant_id': tenantId,
        'p_reason': reason.trim(),
      },
    );
  }

  @override
  Future<String> claimTenantInvite(String inviteCode) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'tenant_claim_invite',
      params: <String, dynamic>{
        'p_invite_code': inviteCode.trim(),
      },
    );
    return res['tenant_id'] as String;
  }
}

/// Seeded in-memory repository for Phase 8 widget tests and local preview.
class InMemoryTenantsRepository implements TenantsRepository {
  InMemoryTenantsRepository() {
    _tenants.addAll(const <TenantItem>[
      TenantItem(
        id: 'ten-karim',
        fullName: 'Karim Traders',
        phone: '01711-223344',
        address: 'Station Road, Bogura',
        status: 'active',
        isPortalLinked: true,
        activeShopCodes: <String>['S-01', 'S-04'],
        securityDepositMinor: 3000000,
        prepaidRentMinor: 500000,
        tenantCreditMinor: 50000,
      ),
      TenantItem(
        id: 'ten-rahim',
        fullName: 'Rahim Enterprise',
        phone: '01819-556677',
        address: 'College Road, Bogura',
        status: 'active',
        isPortalLinked: false,
        activeShopCodes: <String>['S-06'],
        securityDepositMinor: 2000000,
        prepaidRentMinor: 300000,
        tenantCreditMinor: 100000,
      ),
      TenantItem(
        id: 'ten-salma',
        fullName: 'Salma Boutique',
        phone: '01912-889900',
        address: 'Former Tenant — Shop S-02',
        status: 'archived',
        isPortalLinked: false,
        activeShopCodes: <String>[],
        securityDepositMinor: 0,
        prepaidRentMinor: 0,
        tenantCreditMinor: 0,
      ),
    ]);
  }

  final List<TenantItem> _tenants = <TenantItem>[];
  final Map<String, String> _pendingCodesToTenantId = <String, String>{};
  int _inviteCounter = 1000;

  @override
  Future<List<TenantItem>> listTenants() async =>
      List<TenantItem>.unmodifiable(_tenants);

  @override
  Future<TenantItem> createTenant({
    required String fullName,
    required String phone,
    String? address,
  }) async {
    if (fullName.trim().isEmpty || phone.trim().isEmpty) {
      throw ArgumentError('VALIDATION_ERROR');
    }
    final created = TenantItem(
      id: 'ten-${_tenants.length + 1}',
      fullName: fullName.trim(),
      phone: phone.trim(),
      address:
          (address == null || address.trim().isEmpty) ? null : address.trim(),
      status: 'active',
      isPortalLinked: false,
      activeShopCodes: const <String>[],
      securityDepositMinor: 0,
      prepaidRentMinor: 0,
      tenantCreditMinor: 0,
    );
    _tenants.insert(0, created);
    return created;
  }

  @override
  Future<TenantItem> archiveTenant(String tenantId) async {
    final index = _tenants.indexWhere((TenantItem t) => t.id == tenantId);
    if (index < 0) {
      throw StateError('TENANT_NOT_FOUND');
    }
    final updated = _tenants[index].copyWith(status: 'archived');
    _tenants[index] = updated;
    return updated;
  }

  @override
  Future<TenantInviteResult> createTenantInvite({
    required String tenantId,
    int expiresInHours = 168,
  }) async {
    final index = _tenants.indexWhere((TenantItem t) => t.id == tenantId);
    if (index < 0) {
      throw StateError('TENANT_NOT_FOUND');
    }
    if (_tenants[index].isPortalLinked) {
      throw StateError('TENANT_ALREADY_LINKED');
    }
    // Supersede any existing pending code for this tenant
    _pendingCodesToTenantId.removeWhere((_, String v) => v == tenantId);
    _inviteCounter++;
    final code = 'RF88$_inviteCounter';
    _pendingCodesToTenantId[code] = tenantId;
    return TenantInviteResult(
      inviteId: 'inv-$_inviteCounter',
      tenantId: tenantId,
      inviteCode: code,
      expiresAt: '2026-12-04T23:59:59Z',
    );
  }

  @override
  Future<void> revokeTenantPortalAccess({
    required String tenantId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('VALIDATION_ERROR');
    }
    final index = _tenants.indexWhere((TenantItem t) => t.id == tenantId);
    if (index < 0) {
      throw StateError('TENANT_NOT_FOUND');
    }
    _pendingCodesToTenantId.removeWhere((_, String v) => v == tenantId);
    _tenants[index] = _tenants[index].copyWith(isPortalLinked: false);
  }

  @override
  Future<String> claimTenantInvite(String inviteCode) async {
    final normalized = inviteCode.trim().toUpperCase();
    final tenantId = _pendingCodesToTenantId.remove(normalized);
    if (tenantId == null) {
      throw StateError('INVITE_INVALID');
    }
    final index = _tenants.indexWhere((TenantItem t) => t.id == tenantId);
    if (index >= 0) {
      _tenants[index] = _tenants[index].copyWith(isPortalLinked: true);
    }
    return tenantId;
  }
}

final tenantsRepositoryProvider = Provider<TenantsRepository>((Ref ref) {
  return InMemoryTenantsRepository();
});

class TenantsFilterState {
  const TenantsFilterState({
    this.searchQuery = '',
    this.statusFilter = 'active',
  });

  final String searchQuery;
  final String statusFilter;

  TenantsFilterState copyWith({
    String? searchQuery,
    String? statusFilter,
  }) {
    return TenantsFilterState(
      searchQuery: searchQuery ?? this.searchQuery,
      statusFilter: statusFilter ?? this.statusFilter,
    );
  }
}

class TenantsFilterNotifier extends Notifier<TenantsFilterState> {
  @override
  TenantsFilterState build() => const TenantsFilterState();

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setStatusFilter(String filter) {
    state = state.copyWith(statusFilter: filter);
  }
}

final tenantsFilterProvider =
    NotifierProvider<TenantsFilterNotifier, TenantsFilterState>(
  TenantsFilterNotifier.new,
);

class TenantsController extends AsyncNotifier<List<TenantItem>> {
  @override
  Future<List<TenantItem>> build() async {
    return ref.watch(tenantsRepositoryProvider).listTenants();
  }

  Future<void> addTenant({
    required String fullName,
    required String phone,
    String? address,
  }) async {
    final repo = ref.read(tenantsRepositoryProvider);
    await repo.createTenant(
      fullName: fullName,
      phone: phone,
      address: address,
    );
    state = AsyncData<List<TenantItem>>(await repo.listTenants());
  }

  Future<TenantInviteResult> generateInvite(String tenantId) async {
    final repo = ref.read(tenantsRepositoryProvider);
    return repo.createTenantInvite(tenantId: tenantId);
  }

  Future<void> revokePortalAccess({
    required String tenantId,
    required String reason,
  }) async {
    final repo = ref.read(tenantsRepositoryProvider);
    await repo.revokeTenantPortalAccess(tenantId: tenantId, reason: reason);
    state = AsyncData<List<TenantItem>>(await repo.listTenants());
  }

  Future<String> claimInvite(String inviteCode) async {
    final repo = ref.read(tenantsRepositoryProvider);
    final tenantId = await repo.claimTenantInvite(inviteCode);
    state = AsyncData<List<TenantItem>>(await repo.listTenants());
    return tenantId;
  }

  Future<void> archiveTenant(String tenantId) async {
    final repo = ref.read(tenantsRepositoryProvider);
    await repo.archiveTenant(tenantId);
    state = AsyncData<List<TenantItem>>(await repo.listTenants());
  }
}

final tenantsControllerProvider =
    AsyncNotifierProvider<TenantsController, List<TenantItem>>(
  TenantsController.new,
);
