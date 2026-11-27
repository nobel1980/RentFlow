import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/core/widgets/async_state_view.dart';
import 'package:rentflow/core/widgets/separate_fund_cards.dart';
import 'package:rentflow/features/tenants/data/tenants_repository.dart';
import 'package:rentflow/features/tenants/domain/tenant_models.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

/// Phase 8 Owner Tenant Management & Portal Invitation / Linking screen.
///
/// Enforces:
/// - Search by name or phone, filter by `active` / `archived` / `all`.
/// - Archive instead of hard-delete so tenant records survive move-out.
/// - Displays separate Security Deposit, Prepaid Rent, and Tenant Credit
///   balances per tenant.
/// - Generates 8-character single-use invite codes (`owner_create_tenant_invite`)
///   and supports audited portal access revocation (`owner_revoke_tenant_access`).
class TenantsScreen extends ConsumerWidget {
  const TenantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(tenantsFilterProvider);
    final tenantsAsync = ref.watch(tenantsControllerProvider);

    final allTenants = tenantsAsync.valueOrNull ?? const <TenantItem>[];
    final filtered = allTenants.where((TenantItem t) {
      if (filter.statusFilter != 'all' && t.status != filter.statusFilter) {
        return false;
      }
      final q = filter.searchQuery.trim().toLowerCase();
      if (q.isEmpty) {
        return true;
      }
      return t.fullName.toLowerCase().contains(q) ||
          t.phone.toLowerCase().contains(q) ||
          (t.address?.toLowerCase().contains(q) ?? false);
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
                key: const Key('tenants_search_field'),
                onChanged: (String value) => ref
                    .read(tenantsFilterProvider.notifier)
                    .setSearchQuery(value),
                decoration: InputDecoration(
                  hintText: l10n.tenantsSearchHint,
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
                key: const Key('add_tenant_button'),
                onPressed: () => _showAddTenantDialog(context, ref),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(l10n.addTenantAction),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: FilterChip(
                  key: const Key('tenant_filter_active'),
                  label: Text(l10n.filterActive),
                  selected: filter.statusFilter == 'active',
                  onSelected: (_) => ref
                      .read(tenantsFilterProvider.notifier)
                      .setStatusFilter('active'),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: FilterChip(
                  key: const Key('tenant_filter_archived'),
                  label: Text(l10n.filterArchived),
                  selected: filter.statusFilter == 'archived',
                  onSelected: (_) => ref
                      .read(tenantsFilterProvider.notifier)
                      .setStatusFilter('archived'),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: FilterChip(
                  key: const Key('tenant_filter_all'),
                  label: Text(l10n.filterAll),
                  selected: filter.statusFilter == 'all',
                  onSelected: (_) => ref
                      .read(tenantsFilterProvider.notifier)
                      .setStatusFilter('all'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncStateView(
            isLoading: tenantsAsync.isLoading,
            isEmpty: filtered.isEmpty,
            errorMessage: tenantsAsync.hasError ? l10n.errorGeneric : null,
            onRetry: () => ref.invalidate(tenantsControllerProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) {
                final tenant = filtered[index];
                return _TenantCard(
                  tenant: tenant,
                  onTap: () => _showTenantDetailSheet(context, tenant.id),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddTenantDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(l10n.addTenantAction),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  key: const Key('new_tenant_name_field'),
                  controller: nameController,
                  decoration: InputDecoration(labelText: l10n.tenantNameLabel),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('new_tenant_phone_field'),
                  controller: phoneController,
                  decoration: InputDecoration(labelText: l10n.tenantPhoneLabel),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('new_tenant_address_field'),
                  controller: addressController,
                  decoration: InputDecoration(
                    labelText: l10n.tenantAddressLabel,
                  ),
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
              key: const Key('save_new_tenant_button'),
              onPressed: () async {
                if (nameController.text.trim().isEmpty ||
                    phoneController.text.trim().isEmpty) {
                  return;
                }
                await ref.read(tenantsControllerProvider.notifier).addTenant(
                      fullName: nameController.text,
                      phone: phoneController.text,
                      address: addressController.text,
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

  Future<void> _showTenantDetailSheet(
    BuildContext context,
    String tenantId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (BuildContext context, ScrollController scrollController) {
            return TenantDetailSheet(
              tenantId: tenantId,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({
    required this.tenant,
    required this.onTap,
  });

  final TenantItem tenant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: Key('tenant_card_${tenant.id}'),
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
                    tenant.fullName,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _PortalLinkBadge(isLinked: tenant.isPortalLinked),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                tenant.phone,
                style: textTheme.bodyMedium,
              ),
              if (tenant.activeShopCodes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  '${l10n.navShops}: ${tenant.activeShopCodes.join(', ')}',
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalLinkBadge extends StatelessWidget {
  const _PortalLinkBadge({required this.isLinked});

  final bool isLinked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fg = isLinked ? const Color(0xFF14532D) : const Color(0xFF475569);
    final bg = isLinked ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9);
    final border = isLinked ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1);
    final label = isLinked ? l10n.portalLinkedBadge : l10n.portalNotLinkedBadge;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isLinked ? Icons.verified_user_outlined : Icons.link_off_outlined,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class TenantDetailSheet extends ConsumerWidget {
  const TenantDetailSheet({
    required this.tenantId,
    required this.scrollController,
    super.key,
  });

  final String tenantId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tenants = ref.watch(tenantsControllerProvider).valueOrNull ??
        const <TenantItem>[];
    final tenant = tenants.firstWhere(
      (TenantItem t) => t.id == tenantId,
      orElse: () => tenants.first,
    );
    final textTheme = Theme.of(context).textTheme;

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
              tenant.fullName,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            _PortalLinkBadge(isLinked: tenant.isPortalLinked),
          ],
        ),
        const SizedBox(height: 6),
        Text(tenant.phone, style: textTheme.bodyMedium),
        if (tenant.address != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(tenant.address!, style: textTheme.bodySmall),
        ],
        const SizedBox(height: 16),
        if (!tenant.isPortalLinked && tenant.isActive)
          FilledButton.icon(
            key: const Key('generate_portal_invite_button'),
            onPressed: () => _handleGenerateInvite(context, ref, tenant.id),
            icon: const Icon(Icons.qr_code_2_outlined),
            label: Text(l10n.generateInviteAction),
          ),
        if (tenant.isPortalLinked)
          OutlinedButton.icon(
            key: const Key('revoke_portal_access_button'),
            onPressed: () => _showRevokeDialog(context, ref, tenant.id),
            icon: const Icon(Icons.link_off_outlined),
            label: Text(l10n.revokePortalAction),
          ),
        const SizedBox(height: 16),
        SeparateFundCards(
          securityDepositMinor: tenant.securityDepositMinor,
          prepaidRentMinor: tenant.prepaidRentMinor,
          tenantCreditMinor: tenant.tenantCreditMinor,
        ),
        if (tenant.isActive) ...<Widget>[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('archive_tenant_button'),
            onPressed: () async {
              await ref
                  .read(tenantsControllerProvider.notifier)
                  .archiveTenant(tenant.id);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.archive_outlined),
            label: Text(l10n.archiveTenantAction),
          ),
        ],
      ],
    );
  }

  Future<void> _handleGenerateInvite(
    BuildContext context,
    WidgetRef ref,
    String tenantId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final invite = await ref
        .read(tenantsControllerProvider.notifier)
        .generateInvite(tenantId);
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(l10n.inviteCodeDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.inviteCodeDialogSubtitle),
              const SizedBox(height: 16),
              Container(
                key: const Key('generated_invite_code_box'),
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  invite.inviteCode,
                  textAlign: TextAlign.center,
                  style:
                      Theme.of(dialogContext).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              key: const Key('close_invite_dialog_button'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.closeAction),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRevokeDialog(
    BuildContext context,
    WidgetRef ref,
    String tenantId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final reasonController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(l10n.revokePortalAction),
          content: TextField(
            key: const Key('revoke_reason_field'),
            controller: reasonController,
            decoration: InputDecoration(labelText: l10n.revokeReasonLabel),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              key: const Key('confirm_revoke_portal_button'),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  return;
                }
                await ref
                    .read(tenantsControllerProvider.notifier)
                    .revokePortalAccess(
                      tenantId: tenantId,
                      reason: reasonController.text,
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
}
