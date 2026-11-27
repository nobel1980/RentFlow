import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rentflow/core/locale/locale_controller.dart';
import 'package:rentflow/core/widgets/separate_fund_cards.dart';
import 'package:rentflow/core/widgets/status_badge.dart';
import 'package:rentflow/features/notices/data/notices_repository.dart';
import 'package:rentflow/features/notices/domain/notice_models.dart';
import 'package:rentflow/features/notices/presentation/notice_submission_sheet.dart';
import 'package:rentflow/features/tenants/data/tenants_repository.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

/// Tenant Portal shell (`RentFlow_Master_Blueprint.md` §13.4 & §13.6).
///
/// Read-only access to the tenant's own shops, obligations, three separate fund
/// balances, and agreement notice submission entry point.
class TenantShellScreen extends ConsumerStatefulWidget {
  const TenantShellScreen({
    this.noticePeriodMonths = 2,
    this.securityDepositMinor = 1000000,
    this.prepaidRentMinor = 300000,
    this.tenantCreditMinor = 50000,
    super.key,
  });

  final int noticePeriodMonths;
  final int securityDepositMinor;
  final int prepaidRentMinor;
  final int tenantCreditMinor;

  @override
  ConsumerState<TenantShellScreen> createState() => _TenantShellScreenState();
}

class _TenantShellScreenState extends ConsumerState<TenantShellScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final agreementAsync = ref.watch(tenantAgreementProvider);
    final notices = ref.watch(tenantNoticesControllerProvider).valueOrNull ??
        const <TerminationNoticeItem>[];

    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.appTitle} · ${l10n.roleTenant}'),
        actions: <Widget>[
          IconButton(
            key: const Key('tenant_locale_toggle_button'),
            tooltip: l10n.languageLabel,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () =>
                ref.read(localeControllerProvider.notifier).toggleLocale(),
            icon: const Icon(Icons.translate_outlined),
          ),
          IconButton(
            key: const Key('switch_to_owner_button'),
            tooltip: l10n.switchToOwnerPreview,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => context.go('/owner'),
            icon: const Icon(Icons.store_mall_directory_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Card(
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
                          l10n.noticeSectionTitle,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const StatusBadge(status: SemanticStatus.occupied),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.noticePeriodMonths(widget.noticePeriodMonths),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      key: const Key('tenant_submit_notice_button'),
                      onPressed: agreementAsync.valueOrNull == null
                          ? null
                          : () => _showNoticeSheet(
                                context,
                                agreementAsync.valueOrNull!,
                              ),
                      icon: const Icon(Icons.assignment_late_outlined),
                      label: Text(l10n.submitNoticeAction),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      key: const Key('tenant_claim_invite_button'),
                      onPressed: () => _showClaimInviteDialog(context),
                      icon: const Icon(Icons.vpn_key_outlined),
                      label: Text(l10n.claimInviteAction),
                    ),
                  ],
                ),
              ),
            ),
            if (notices.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                l10n.submittedNoticesTimelineTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              ...notices.map(
                (TerminationNoticeItem notice) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    key: Key('submitted_notice_card_${notice.noticeId}'),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${notice.agreementNumber} · ${notice.requestedTerminationDate}',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                              'Status: ${notice.status} · Served: ${notice.servedAt}'),
                          if (notice.status == 'submitted') ...<Widget>[
                            const SizedBox(height: 8),
                            OutlinedButton(
                              key: Key(
                                'withdraw_notice_button_${notice.noticeId}',
                              ),
                              onPressed: () => ref
                                  .read(
                                      tenantNoticesControllerProvider.notifier)
                                  .requestWithdrawal(
                                    noticeId: notice.noticeId,
                                    reason: 'Tenant requested withdrawal',
                                  ),
                              child: Text(l10n.requestWithdrawalAction),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SeparateFundCards(
              securityDepositMinor: widget.securityDepositMinor,
              prepaidRentMinor: widget.prepaidRentMinor,
              tenantCreditMinor: widget.tenantCreditMinor,
            ),
          ],
        ),
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
            icon: const Icon(Icons.storefront_outlined),
            label: l10n.navMyShops,
          ),
          NavigationDestination(
            icon: const Icon(Icons.payments_outlined),
            label: l10n.navMyRent,
          ),
          NavigationDestination(
            icon: const Icon(Icons.description_outlined),
            label: l10n.navMyAgreement,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }

  Future<void> _showNoticeSheet(
    BuildContext context,
    TenantAgreementSummary agreement,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          maxChildSize: 0.94,
          minChildSize: 0.5,
          builder: (BuildContext context, ScrollController scrollController) {
            return NoticeSubmissionSheet(
              agreement: agreement,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  Future<void> _showClaimInviteDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final codeController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(l10n.claimInviteAction),
          content: TextField(
            key: const Key('claim_invite_code_field'),
            controller: codeController,
            decoration: InputDecoration(labelText: l10n.enterInviteCodeLabel),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              key: const Key('confirm_claim_invite_button'),
              onPressed: () async {
                if (codeController.text.trim().isEmpty) {
                  return;
                }
                await ref
                    .read(tenantsControllerProvider.notifier)
                    .claimInvite(codeController.text);
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
