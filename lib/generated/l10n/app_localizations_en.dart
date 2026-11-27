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
  String get cancelAction => 'Cancel';

  @override
  String get saveAction => 'Save';

  @override
  String get closeAction => 'Close';

  @override
  String get filterAll => 'All';

  @override
  String get filterActive => 'Active';

  @override
  String get filterArchived => 'Archived';

  @override
  String get shopsSearchHint => 'Search shop code, name or floor...';

  @override
  String get addShopAction => 'Add Shop';

  @override
  String get addPropertyAction => 'Add Property';

  @override
  String get shopCodeLabel => 'Shop Code (e.g. S-12)';

  @override
  String get shopNameLabel => 'Display Name';

  @override
  String get shopFloorLabel => 'Floor / Section (Optional)';

  @override
  String get currentTenantLabel => 'Current Tenant';

  @override
  String get currentRentLabel => 'Monthly Rent';

  @override
  String get noActiveTenantLabel => 'Vacant — Ready for New Agreement';

  @override
  String get occupancyHistoryTitle => 'Occupancy History Timeline (Owner Only)';

  @override
  String get occupancyHistorySubtitle =>
      'Every previous tenant, agreement, rent snapshot, and move-out record is permanently preserved when a shop becomes vacant.';

  @override
  String get historyStatusActive => 'Active Occupancy';

  @override
  String get historyStatusEnded => 'Past Occupancy (Ended)';

  @override
  String get setMaintenanceAction => 'Set Maintenance';

  @override
  String get setActiveUnitAction => 'Mark Available';

  @override
  String get tenantsSearchHint => 'Search tenant name or phone...';

  @override
  String get addTenantAction => 'Add Tenant';

  @override
  String get tenantNameLabel => 'Full Name';

  @override
  String get tenantPhoneLabel => 'Phone Number';

  @override
  String get tenantAddressLabel => 'Address / Notes (Optional)';

  @override
  String get portalLinkedBadge => 'Portal Linked';

  @override
  String get portalNotLinkedBadge => 'Not Linked';

  @override
  String get generateInviteAction => 'Generate Portal Invite Code';

  @override
  String get inviteCodeDialogTitle => 'Single-Use Tenant Invite Code';

  @override
  String get inviteCodeDialogSubtitle =>
      'Share this 8-character code with the tenant. Previous pending codes are automatically superseded.';

  @override
  String get revokePortalAction => 'Revoke Portal Access';

  @override
  String get revokeReasonLabel => 'Reason for revoking portal access';

  @override
  String get archiveTenantAction => 'Archive Tenant Record';

  @override
  String get claimInviteAction => 'Link Tenant Portal Code';

  @override
  String get enterInviteCodeLabel => '8-Character Invite Code';

  @override
  String get obligationsSectionTitle => 'Shop & Month Rent Obligations';

  @override
  String get dueDateLabel => 'Due Date';

  @override
  String get billingPeriodLabel => 'Billing Month';

  @override
  String get baseRentLabel => 'Base Rent Snapshot';

  @override
  String get netAdjustmentLabel => 'Net Adjustments';

  @override
  String get adjustedPayableLabel => 'Adjusted Payable';

  @override
  String get settledAmountLabel => 'Settled';

  @override
  String get remainingDueLabel => 'Remaining Due';

  @override
  String get adjustRentAction => 'Adjust Rent';

  @override
  String get adjustmentTypeDebit => 'Debit (Additional Charge)';

  @override
  String get adjustmentTypeCredit => 'Credit (Discount)';

  @override
  String get adjustmentAmountLabel => 'Adjustment Amount (BDT)';

  @override
  String get adjustmentReasonLabel => 'Mandatory Reason / Description';

  @override
  String get collectPaymentTitle => 'Collect Multi-Shop / Multi-Month Payment';

  @override
  String get paymentAmountLabel => 'Received Payment Amount (BDT)';

  @override
  String get paymentMethodLabel => 'Payment Method';

  @override
  String get methodCash => 'Cash';

  @override
  String get methodBank => 'Bank Transfer';

  @override
  String get methodMfs => 'Mobile Financial Service (bKash/Nagad)';

  @override
  String get proposeOldestDueAction => 'Propose Oldest-Due-First';

  @override
  String get proposalReviewBanner =>
      'Review Proposed Allocations — Owner Confirmation Required Before Posting';

  @override
  String get rentAllocatedTotalLabel => 'Total Rent Allocated';

  @override
  String get excessToTenantCreditLabel => 'Excess → Tenant Credit (Atomic)';

  @override
  String get confirmAndPostPaymentAction => 'Confirm & Post Payment';

  @override
  String get receiptDialogTitle => 'Payment Receipt Posted';

  @override
  String get receiptNumberLabel => 'Receipt No';

  @override
  String get reportAccrualTitle => 'Billing-Period Accrual Report';

  @override
  String get reportAccrualSubtitle =>
      'Obligations grouped by billing month (e.g. October rent paid in November is accrued to October).';

  @override
  String get reportCashTitle => 'Cash Collection by Payment Date';

  @override
  String get reportCashSubtitle =>
      'Actual cash received during the selected payment dates (Security Deposits are excluded).';

  @override
  String get cashReceivedTotalLabel => 'Total Cash Received';

  @override
  String get reconciliationVerifiedBanner =>
      'Reconciled: Cash Received = Rent Allocated + Tenant Credit Created';

  @override
  String get monthlyAccrualBreakdownTitle => 'Month-by-Month Accrual Breakdown';

  @override
  String get noticeSheetTitle => 'Submit Termination / Non-Renewal Notice';

  @override
  String get noticeTypeLabel => 'Notice Type';

  @override
  String get noticeTypeNonRenewal => 'Non-Renewal at Contract Expiry';

  @override
  String get noticeTypeEarlyTermination => 'Early Termination Request';

  @override
  String get noticeReasonLabel => 'Reason / Handover Note';

  @override
  String get selectShopsToVacateLabel => 'Select Shops Included in Notice';

  @override
  String get confirmSubmitNoticeAction => 'Confirm & Serve Immutable Notice';

  @override
  String get submittedNoticesTimelineTitle =>
      'Submitted Notices & Status Timeline';

  @override
  String get requestWithdrawalAction => 'Request Withdrawal';

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
