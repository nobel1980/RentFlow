// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'RentFlow';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navShops => 'Shops';

  @override
  String get navTenants => 'Tenants';

  @override
  String get navPayments => 'Payments';

  @override
  String get navReports => 'Reports';

  @override
  String get navMyShops => 'My Shops';

  @override
  String get navMyRent => 'Rent & Dues';

  @override
  String get navMyAgreement => 'Agreement & Notice';

  @override
  String get navSettings => 'Settings';

  @override
  String get roleOwner => 'Owner';

  @override
  String get roleTenant => 'Tenant';

  @override
  String get languageLabel => 'Language';

  @override
  String get languageBangla => 'বাংলা (Bangla)';

  @override
  String get languageEnglish => 'English';

  @override
  String get switchRolePreview => 'Preview Tenant Portal';

  @override
  String get switchToOwnerPreview => 'Back to Owner View';

  @override
  String get fundSectionTitle => 'Separate Tenant Fund Balances';

  @override
  String get fundSectionSubtitle =>
      'Refundable deposit, prepaid rent, and excess payment credit are tracked in separate ledgers and never combined.';

  @override
  String get securityDepositTitle => 'Security Deposit';

  @override
  String get securityDepositCaption =>
      'Refundable security deposit (not rent income)';

  @override
  String get prepaidRentTitle => 'Prepaid Advance Rent';

  @override
  String get prepaidRentCaption =>
      'Explicitly received for future billing periods';

  @override
  String get tenantCreditTitle => 'Tenant Credit';

  @override
  String get tenantCreditCaption =>
      'Unallocated excess payment held for future rent';

  @override
  String get statusPaid => 'Paid';

  @override
  String get statusPartiallyPaid => 'Partially Paid';

  @override
  String get statusDue => 'Due Today';

  @override
  String get statusOverdue => 'Overdue';

  @override
  String get statusUpcoming => 'Upcoming';

  @override
  String get statusOccupied => 'Occupied';

  @override
  String get statusVacant => 'Vacant';

  @override
  String get statusMaintenance => 'Maintenance';

  @override
  String get billingOverviewTitle => 'Current Month Rent Accrual';

  @override
  String get expectedRentLabel => 'Expected Rent';

  @override
  String get collectedAllocatedLabel => 'Allocated Rent Settled';

  @override
  String get outstandingRentLabel => 'Outstanding Balance';

  @override
  String get overdueRentLabel => 'Overdue Balance';

  @override
  String get occupancyOverviewTitle => 'Shop Occupancy (No Unit Cap)';

  @override
  String get totalUnitsLabel => 'Total Shops';

  @override
  String get occupiedUnitsLabel => 'Occupied';

  @override
  String get vacantUnitsLabel => 'Vacant';

  @override
  String get noticeSectionTitle => 'Termination & Non-Renewal Notice Policy';

  @override
  String noticePeriodMonths(int months) {
    return '$months-Calendar-Month Notice Period';
  }

  @override
  String get submitNoticeAction => 'Submit Non-Renewal / Termination Notice';

  @override
  String get recordPaymentAction => 'Record Rent Payment';

  @override
  String get retryAction => 'Retry';

  @override
  String get emptyStateTitle => 'No records found';

  @override
  String get loadingLabel => 'Loading...';

  @override
  String get errorNotAuthorized =>
      'You are not authorized to perform this action.';

  @override
  String get errorTenantNotLinked =>
      'Your tenant account is not linked to a verified tenancy record yet.';

  @override
  String get errorAgreementNotFound => 'Agreement was not found.';

  @override
  String get errorAgreementNotActive => 'Agreement is not currently active.';

  @override
  String get errorAgreementNumberExists =>
      'An agreement with this reference number already exists.';

  @override
  String get errorUnitNotAvailable =>
      'Selected shop is already occupied or reserved for an overlapping date range.';

  @override
  String get errorObligationNotFound => 'Rent obligation was not found.';

  @override
  String get errorAdjustmentWouldNegateRent =>
      'This adjustment would reduce payable rent below zero or below the already-settled amount.';

  @override
  String get errorAllocationExceedsOutstanding =>
      'Allocation exceeds the current outstanding balance for one or more obligations.';

  @override
  String get errorPaymentAllocationMismatch =>
      'Total rent allocations cannot exceed the received payment amount.';

  @override
  String get errorPaymentCreditAlreadyUsed =>
      'Payment cannot be reversed because the tenant credit created from its excess has already been used.';

  @override
  String get errorInsufficientSecurityDeposit =>
      'Amount exceeds the available security deposit balance for this agreement.';

  @override
  String get errorInsufficientPrepaidRent =>
      'Amount exceeds the available prepaid advance rent balance.';

  @override
  String get errorInsufficientTenantCredit =>
      'Amount exceeds the available tenant credit balance.';

  @override
  String get errorDepositApplicationNotAuthorized =>
      'Security deposit application requires agreement permission, owner confirmation, and a recorded reason.';

  @override
  String get errorNoticeNotAllowed =>
      'Early termination is not permitted under the signed agreement terms.';

  @override
  String get errorNoticePeriodNotMet =>
      'Requested date does not meet the required calendar-month notice period.';

  @override
  String get errorPartialTerminationNotAllowed =>
      'Partial shop termination is not permitted under this agreement.';

  @override
  String get errorActiveNoticeExists =>
      'An active termination notice already exists for one or more selected shops.';

  @override
  String get errorPostMoveOutSettled =>
      'Cannot complete move-out while a post-move-out billing period has applied payments or credits.';

  @override
  String get errorIdempotencyConflict =>
      'A different request was already submitted with this idempotency key.';

  @override
  String get errorValidation => 'Please check your inputs and try again.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';
}
