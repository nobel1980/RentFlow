import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/features/notices/data/notices_repository.dart';
import 'package:rentflow/features/notices/domain/notice_models.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

/// Phase 14 & 17 Tenant Notice Submission bottom sheet
/// (`tenant_submit_termination_notice`).
class NoticeSubmissionSheet extends ConsumerStatefulWidget {
  const NoticeSubmissionSheet({
    required this.agreement,
    required this.scrollController,
    super.key,
  });

  final TenantAgreementSummary agreement;
  final ScrollController scrollController;

  @override
  ConsumerState<NoticeSubmissionSheet> createState() =>
      _NoticeSubmissionSheetState();
}

class _NoticeSubmissionSheetState extends ConsumerState<NoticeSubmissionSheet> {
  String _noticeType = 'non_renewal';
  final TextEditingController _reasonController = TextEditingController();
  late final Set<String> _selectedUnitIds;

  @override
  void initState() {
    super.initState();
    _selectedUnitIds = widget.agreement.units
        .map((TenantAgreementUnitItem u) => u.agreementUnitId)
        .toSet();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final agr = widget.agreement;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          l10n.noticeSheetTitle,
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          '${agr.agreementNumber} · ${l10n.noticePeriodMonths(agr.tenantNoticePeriodMonths)}',
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: const Key('notice_type_dropdown'),
          isExpanded: true,
          initialValue: _noticeType,
          decoration: InputDecoration(
            labelText: l10n.noticeTypeLabel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          items: <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: 'non_renewal',
              child: Text(l10n.noticeTypeNonRenewal),
            ),
            if (agr.earlyTerminationAllowed)
              DropdownMenuItem<String>(
                value: 'early_termination',
                child: Text(l10n.noticeTypeEarlyTermination),
              ),
          ],
          onChanged: (String? value) {
            if (value != null) {
              setState(() {
                _noticeType = value;
              });
            }
          },
        ),
        const SizedBox(height: 14),
        Text(
          l10n.selectShopsToVacateLabel,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        ...agr.units.map((TenantAgreementUnitItem unit) {
          final isChecked = _selectedUnitIds.contains(unit.agreementUnitId);
          return CheckboxListTile(
            key: Key('notice_unit_checkbox_${unit.unitCode}'),
            value: isChecked,
            onChanged: agr.partialUnitTerminationAllowed
                ? (bool? checked) {
                    setState(() {
                      if (checked == true) {
                        _selectedUnitIds.add(unit.agreementUnitId);
                      } else if (_selectedUnitIds.length > 1) {
                        _selectedUnitIds.remove(unit.agreementUnitId);
                      }
                    });
                  }
                : null,
            title: Text('${unit.unitCode} · ${unit.unitName}'),
          );
        }),
        const SizedBox(height: 12),
        TextField(
          key: const Key('notice_reason_field'),
          controller: _reasonController,
          decoration: InputDecoration(
            labelText: l10n.noticeReasonLabel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('confirm_submit_notice_button'),
          onPressed: _selectedUnitIds.isEmpty
              ? null
              : () async {
                  await ref
                      .read(tenantNoticesControllerProvider.notifier)
                      .submitNotice(
                        agreementId: agr.agreementId,
                        noticeType: _noticeType,
                        agreementUnitIds: _selectedUnitIds.toList(),
                        reason: _reasonController.text,
                      );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
          icon: const Icon(Icons.send_outlined),
          label: Text(l10n.confirmSubmitNoticeAction),
        ),
      ],
    );
  }
}
