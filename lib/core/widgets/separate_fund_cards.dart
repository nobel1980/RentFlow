import 'package:flutter/material.dart';
import 'package:rentflow/core/money/money_formatter.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

/// Displays Security Deposit, Prepaid Advance Rent, and Tenant Credit in
/// three distinct cards so the balances are never merged (`AGENTS.md`).
class SeparateFundCards extends StatelessWidget {
  const SeparateFundCards({
    required this.securityDepositMinor,
    required this.prepaidRentMinor,
    required this.tenantCreditMinor,
    super.key,
  });

  static const Key securityDepositCardKey = Key('fund_card_security_deposit');
  static const Key prepaidRentCardKey = Key('fund_card_prepaid_rent');
  static const Key tenantCreditCardKey = Key('fund_card_tenant_credit');

  final int securityDepositMinor;
  final int prepaidRentMinor;
  final int tenantCreditMinor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeCode = Localizations.localeOf(context).toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.fundSectionTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.fundSectionSubtitle,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        _FundLedgerTile(
          key: securityDepositCardKey,
          icon: Icons.shield_outlined,
          accentColor: const Color(0xFF0F766E),
          title: l10n.securityDepositTitle,
          caption: l10n.securityDepositCaption,
          formattedAmount: MoneyFormatter.formatMinor(
            securityDepositMinor,
            locale: localeCode,
          ),
        ),
        const SizedBox(height: 10),
        _FundLedgerTile(
          key: prepaidRentCardKey,
          icon: Icons.calendar_month_outlined,
          accentColor: const Color(0xFF1D4ED8),
          title: l10n.prepaidRentTitle,
          caption: l10n.prepaidRentCaption,
          formattedAmount: MoneyFormatter.formatMinor(
            prepaidRentMinor,
            locale: localeCode,
          ),
        ),
        const SizedBox(height: 10),
        _FundLedgerTile(
          key: tenantCreditCardKey,
          icon: Icons.account_balance_wallet_outlined,
          accentColor: const Color(0xFF7C3AED),
          title: l10n.tenantCreditTitle,
          caption: l10n.tenantCreditCaption,
          formattedAmount: MoneyFormatter.formatMinor(
            tenantCreditMinor,
            locale: localeCode,
          ),
        ),
      ],
    );
  }
}

class _FundLedgerTile extends StatelessWidget {
  const _FundLedgerTile({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.caption,
    required this.formattedAmount,
    super.key,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String caption;
  final String formattedAmount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formattedAmount,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
