import 'package:flutter/material.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

enum SemanticStatus {
  paid,
  partiallyPaid,
  dueToday,
  overdue,
  upcoming,
  occupied,
  vacant,
  maintenance,
}

/// Accessible status chip that pairs an explicit icon and localized text label
/// with semantic colors so color is never used alone (`AGENTS.md` UI/UX rule).
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.status,
    super.key,
  });

  final SemanticStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spec = _resolveSpec(status, l10n);

    return Semantics(
      label: spec.label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: spec.backgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: spec.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(spec.icon, size: 16, color: spec.foregroundColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                spec.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: spec.foregroundColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _BadgeSpec _resolveSpec(SemanticStatus status, AppLocalizations l10n) {
    switch (status) {
      case SemanticStatus.paid:
        return _BadgeSpec(
          label: l10n.statusPaid,
          icon: Icons.check_circle_outline,
          foregroundColor: const Color(0xFF14532D),
          backgroundColor: const Color(0xFFDCFCE7),
          borderColor: const Color(0xFF86EFAC),
        );
      case SemanticStatus.partiallyPaid:
        return _BadgeSpec(
          label: l10n.statusPartiallyPaid,
          icon: Icons.timelapse_outlined,
          foregroundColor: const Color(0xFF78350F),
          backgroundColor: const Color(0xFFFEF3C7),
          borderColor: const Color(0xFFFCD34D),
        );
      case SemanticStatus.dueToday:
        return _BadgeSpec(
          label: l10n.statusDue,
          icon: Icons.event_available_outlined,
          foregroundColor: const Color(0xFF7C2D12),
          backgroundColor: const Color(0xFFFFEDD5),
          borderColor: const Color(0xFFFDBA74),
        );
      case SemanticStatus.overdue:
        return _BadgeSpec(
          label: l10n.statusOverdue,
          icon: Icons.warning_amber_rounded,
          foregroundColor: const Color(0xFF7F1D1D),
          backgroundColor: const Color(0xFFFEE2E2),
          borderColor: const Color(0xFFFCA5A5),
        );
      case SemanticStatus.upcoming:
        return _BadgeSpec(
          label: l10n.statusUpcoming,
          icon: Icons.schedule_outlined,
          foregroundColor: const Color(0xFF1E3A8A),
          backgroundColor: const Color(0xFFDBEAFE),
          borderColor: const Color(0xFF93C5FD),
        );
      case SemanticStatus.occupied:
        return _BadgeSpec(
          label: l10n.statusOccupied,
          icon: Icons.storefront_outlined,
          foregroundColor: const Color(0xFF0F766E),
          backgroundColor: const Color(0xFFCCFBF1),
          borderColor: const Color(0xFF5EEAD4),
        );
      case SemanticStatus.vacant:
        return _BadgeSpec(
          label: l10n.statusVacant,
          icon: Icons.meeting_room_outlined,
          foregroundColor: const Color(0xFF334155),
          backgroundColor: const Color(0xFFF1F5F9),
          borderColor: const Color(0xFFCBD5E1),
        );
      case SemanticStatus.maintenance:
        return _BadgeSpec(
          label: l10n.statusMaintenance,
          icon: Icons.build_circle_outlined,
          foregroundColor: const Color(0xFF78350F),
          backgroundColor: const Color(0xFFFEF3C7),
          borderColor: const Color(0xFFFCD34D),
        );
    }
  }
}

class _BadgeSpec {
  const _BadgeSpec({
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
  });

  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;
}
