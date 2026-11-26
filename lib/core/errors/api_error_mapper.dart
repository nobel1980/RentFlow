import 'package:rentflow/generated/l10n/app_localizations.dart';

/// Maps stable PostgreSQL `P0001` error codes from migrations `0003`–`0011`
/// to user-friendly localized messages in Bangla or English.
class ApiErrorMapper {
  const ApiErrorMapper._();

  static String localizeCode(String? code, AppLocalizations l10n) {
    switch (code?.trim()) {
      case 'NOT_AUTHORIZED':
      case 'FORBIDDEN':
      case 'AUTH_REQUIRED':
        return l10n.errorNotAuthorized;
      case 'TENANT_PROFILE_NOT_LINKED':
        return l10n.errorTenantNotLinked;
      case 'AGREEMENT_NOT_FOUND':
        return l10n.errorAgreementNotFound;
      case 'AGREEMENT_NOT_ACTIVE':
        return l10n.errorAgreementNotActive;
      case 'AGREEMENT_NUMBER_EXISTS':
        return l10n.errorAgreementNumberExists;
      case 'UNIT_NOT_AVAILABLE_FOR_DATE_RANGE':
      case 'UNIT_ALREADY_OCCUPIED':
        return l10n.errorUnitNotAvailable;
      case 'OBLIGATION_NOT_FOUND':
        return l10n.errorObligationNotFound;
      case 'ADJUSTMENT_WOULD_NEGATE_RENT':
        return l10n.errorAdjustmentWouldNegateRent;
      case 'ALLOCATION_EXCEEDS_OUTSTANDING':
      case 'PAYMENT_ALLOCATION_EXCEEDS_OUTSTANDING':
        return l10n.errorAllocationExceedsOutstanding;
      case 'PAYMENT_ALLOCATION_MISMATCH':
        return l10n.errorPaymentAllocationMismatch;
      case 'PAYMENT_CREDIT_ALREADY_USED':
      case 'FUND_BALANCE_ALREADY_USED':
        return l10n.errorPaymentCreditAlreadyUsed;
      case 'INSUFFICIENT_SECURITY_DEPOSIT':
      case 'INSUFFICIENT_DEPOSIT_BALANCE':
        return l10n.errorInsufficientSecurityDeposit;
      case 'INSUFFICIENT_PREPAID_RENT':
        return l10n.errorInsufficientPrepaidRent;
      case 'INSUFFICIENT_TENANT_CREDIT':
        return l10n.errorInsufficientTenantCredit;
      case 'SECURITY_DEPOSIT_APPLICATION_NOT_AUTHORIZED':
        return l10n.errorDepositApplicationNotAuthorized;
      case 'NOTICE_NOT_ALLOWED_BY_AGREEMENT':
        return l10n.errorNoticeNotAllowed;
      case 'NOTICE_PERIOD_NOT_MET':
        return l10n.errorNoticePeriodNotMet;
      case 'PARTIAL_TERMINATION_NOT_ALLOWED':
        return l10n.errorPartialTerminationNotAllowed;
      case 'ACTIVE_NOTICE_ALREADY_EXISTS':
        return l10n.errorActiveNoticeExists;
      case 'POST_MOVE_OUT_OBLIGATION_HAS_SETTLEMENTS':
        return l10n.errorPostMoveOutSettled;
      case 'IDEMPOTENCY_CONFLICT':
        return l10n.errorIdempotencyConflict;
      case 'VALIDATION_ERROR':
        return l10n.errorValidation;
      default:
        return l10n.errorGeneric;
    }
  }
}
