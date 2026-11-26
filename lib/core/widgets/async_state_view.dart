import 'package:flutter/material.dart';
import 'package:rentflow/generated/l10n/app_localizations.dart';

/// Standard Loading / Empty / Error state wrapper (`AGENTS.md` UI/UX rule).
class AsyncStateView extends StatelessWidget {
  const AsyncStateView({
    required this.isLoading,
    required this.isEmpty,
    required this.child,
    this.errorMessage,
    this.emptyMessage,
    this.onRetry,
    super.key,
  });

  final bool isLoading;
  final bool isEmpty;
  final String? errorMessage;
  final String? emptyMessage;
  final VoidCallback? onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(l10n.loadingLabel),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.error_outline,
                size: 40,
                color: Color(0xFFB91C1C),
              ),
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...<Widget>[
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.retryAction),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.inbox_outlined,
                size: 40,
                color: Color(0xFF64748B),
              ),
              const SizedBox(height: 12),
              Text(
                emptyMessage ?? l10n.emptyStateTitle,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return child;
  }
}
