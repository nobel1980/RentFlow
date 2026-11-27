// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class AppLocalizationsBn extends AppLocalizations {
  AppLocalizationsBn([String locale = 'bn']) : super(locale);

  @override
  String get appTitle => 'রেন্টফ্লো';

  @override
  String get navDashboard => 'ড্যাশবোর্ড';

  @override
  String get navShops => 'দোকানসমূহ';

  @override
  String get navTenants => 'ভাড়াটিয়া';

  @override
  String get navPayments => 'ভাড়া আদায়';

  @override
  String get navReports => 'রিপোর্ট';

  @override
  String get navMyShops => 'আমার দোকান';

  @override
  String get navMyRent => 'ভাড়া ও বকেয়া';

  @override
  String get navMyAgreement => 'চুক্তি ও নোটিশ';

  @override
  String get navSettings => 'সেটিংস';

  @override
  String get roleOwner => 'মালিক';

  @override
  String get roleTenant => 'ভাড়াটিয়া';

  @override
  String get languageLabel => 'ভাষা';

  @override
  String get languageBangla => 'বাংলা (Bangla)';

  @override
  String get languageEnglish => 'English';

  @override
  String get switchRolePreview => 'ভাড়াটিয়া পোর্টাল প্রিভিউ';

  @override
  String get switchToOwnerPreview => 'মালিক ভিউতে ফিরুন';

  @override
  String get fundSectionTitle => 'ভাড়াটিয়ার পৃথক তহবিল হিসাব';

  @override
  String get fundSectionSubtitle =>
      'ফেরতযোগ্য জামানত, অগ্রিম ভাড়া এবং অতিরিক্ত পরিশোধের ক্রেডিট তিনটি সম্পূর্ণ পৃথক খাতায় রাখা হয় এবং কখনো একত্র করা হয় না।';

  @override
  String get securityDepositTitle => 'জামানত (Security Deposit)';

  @override
  String get securityDepositCaption => 'ফেরতযোগ্য জামানত — এটি ভাড়া আয় নয়';

  @override
  String get prepaidRentTitle => 'অগ্রিম ভাড়া (Prepaid Rent)';

  @override
  String get prepaidRentCaption =>
      'ভবিষ্যৎ মাসের ভাড়ার জন্য নির্দিষ্টভাবে প্রাপ্ত';

  @override
  String get tenantCreditTitle => 'ভাড়াটিয়া ক্রেডিট (Tenant Credit)';

  @override
  String get tenantCreditCaption =>
      'ভাড়ার অতিরিক্ত প্রদত্ত অর্থ যা ভবিষ্যৎ ভাড়ায় সমন্বয়যোগ্য';

  @override
  String get statusPaid => 'পরিশোধিত';

  @override
  String get statusPartiallyPaid => 'আংশিক পরিশোধিত';

  @override
  String get statusDue => 'আজ প্রদেয়';

  @override
  String get statusOverdue => 'বকেয়া (মেয়াদোত্তীর্ণ)';

  @override
  String get statusUpcoming => 'আসন্ন';

  @override
  String get statusOccupied => 'ভাড়াকৃত';

  @override
  String get statusVacant => 'খালি';

  @override
  String get statusMaintenance => 'মেরামতাধীন';

  @override
  String get billingOverviewTitle => 'চলতি মাসের ভাড়ার হিসাব';

  @override
  String get expectedRentLabel => 'মোট নির্ধারিত ভাড়া';

  @override
  String get collectedAllocatedLabel => 'সমন্বয়কৃত আদায়';

  @override
  String get outstandingRentLabel => 'মোট অপরিশোধিত ভাড়া';

  @override
  String get overdueRentLabel => 'মেয়াদোত্তীর্ণ বকেয়া';

  @override
  String get occupancyOverviewTitle => 'দোকানের অবস্থা (সংখ্যার কোনো সীমা নেই)';

  @override
  String get totalUnitsLabel => 'মোট দোকান';

  @override
  String get occupiedUnitsLabel => 'ভাড়াকৃত';

  @override
  String get vacantUnitsLabel => 'খালি';

  @override
  String get noticeSectionTitle => 'চুক্তি সমাপ্তি ও নবায়ন না করার নোটিশ নীতি';

  @override
  String noticePeriodMonths(int months) {
    return '$months ক্যালেন্ডার মাসের নোটিশ মেয়াদ';
  }

  @override
  String get submitNoticeAction => 'চুক্তি সমাপ্তির নোটিশ দিন';

  @override
  String get recordPaymentAction => 'ভাড়া আদায় এন্ট্রি করুন';

  @override
  String get retryAction => 'পুনরায় চেষ্টা করুন';

  @override
  String get emptyStateTitle => 'কোনো তথ্য পাওয়া যায়নি';

  @override
  String get loadingLabel => 'লোড হচ্ছে...';

  @override
  String get cancelAction => 'বাতিল';

  @override
  String get saveAction => 'সংরক্ষণ করুন';

  @override
  String get closeAction => 'বন্ধ করুন';

  @override
  String get filterAll => 'সবগুলো';

  @override
  String get filterActive => 'সক্রিয়';

  @override
  String get filterArchived => 'আর্কাইভকৃত';

  @override
  String get shopsSearchHint => 'দোকানের কোড, নাম বা ফ্লোর খুঁজুন...';

  @override
  String get addShopAction => 'নতুন দোকান যোগ করুন';

  @override
  String get addPropertyAction => 'নতুন মার্কেট/প্রপার্টি';

  @override
  String get shopCodeLabel => 'দোকান কোড (যেমন S-12)';

  @override
  String get shopNameLabel => 'দোকানের নাম';

  @override
  String get shopFloorLabel => 'ফ্লোর / সেকশন (ঐচ্ছিক)';

  @override
  String get currentTenantLabel => 'বর্তমান ভাড়াটিয়া';

  @override
  String get currentRentLabel => 'মাসিক ভাড়া';

  @override
  String get noActiveTenantLabel => 'খালি — নতুন চুক্তির জন্য প্রস্তুত';

  @override
  String get occupancyHistoryTitle =>
      'ভাড়াটিয়ার ইতিহাস টাইমলাইন (শুধুমাত্র মালিকের জন্য)';

  @override
  String get occupancyHistorySubtitle =>
      'দোকান খালি হলেও পূর্ববর্তী সকল ভাড়াটিয়া, চুক্তি, ভাড়ার পরিমাণ এবং মুভ-আউট রেকর্ড স্থায়ীভাবে সংরক্ষিত থাকে।';

  @override
  String get historyStatusActive => 'বর্তমান ভাড়াটিয়া';

  @override
  String get historyStatusEnded => 'পূর্ববর্তী ভাড়াটিয়া (সমাপ্ত)';

  @override
  String get setMaintenanceAction => 'মেরামতাধীন রাখুন';

  @override
  String get setActiveUnitAction => 'ভাড়ার জন্য সক্রিয় করুন';

  @override
  String get tenantsSearchHint => 'ভাড়াটিয়ার নাম বা ফোন নম্বর খুঁজুন...';

  @override
  String get addTenantAction => 'নতুন ভাড়াটিয়া যোগ করুন';

  @override
  String get tenantNameLabel => 'পূর্ণ নাম';

  @override
  String get tenantPhoneLabel => 'মোবাইল নম্বর';

  @override
  String get tenantAddressLabel => 'ঠিকানা / নোট (ঐচ্ছিক)';

  @override
  String get portalLinkedBadge => 'পোর্টাল যুক্ত';

  @override
  String get portalNotLinkedBadge => 'পোর্টাল যুক্ত নয়';

  @override
  String get generateInviteAction => 'পোর্টাল ইনভাইট কোড তৈরি করুন';

  @override
  String get inviteCodeDialogTitle =>
      'একবার ব্যবহারযোগ্য ভাড়াটিয়া ইনভাইট কোড';

  @override
  String get inviteCodeDialogSubtitle =>
      'এই ৮-অক্ষরের কোডটি ভাড়াটিয়াকে দিন। নতুন কোড তৈরি করলে পূর্বের অব্যবহৃত কোড স্বয়ংক্রিয়ভাবে বাতিল হয়ে যায়।';

  @override
  String get revokePortalAction => 'পোর্টাল অ্যাক্সেস বাতিল করুন';

  @override
  String get revokeReasonLabel => 'পোর্টাল অ্যাক্সেস বাতিলের কারণ';

  @override
  String get archiveTenantAction => 'ভাড়াটিয়া আর্কাইভ করুন';

  @override
  String get claimInviteAction => 'ভাড়াটিয়া পোর্টাল কোড যুক্ত করুন';

  @override
  String get enterInviteCodeLabel => '৮-অক্ষরের ইনভাইট কোড';

  @override
  String get obligationsSectionTitle => 'দোকান ও মাসভিত্তিক ভাড়ার তালিকা';

  @override
  String get dueDateLabel => 'পরিশোধের শেষ তারিখ';

  @override
  String get billingPeriodLabel => 'ভাড়ার মাস';

  @override
  String get baseRentLabel => 'মূল ভাড়া';

  @override
  String get netAdjustmentLabel => 'সমন্বয় (চার্জ/ছাড়)';

  @override
  String get adjustedPayableLabel => 'সমন্বিত প্রদেয় ভাড়া';

  @override
  String get settledAmountLabel => 'পরিশোধিত';

  @override
  String get remainingDueLabel => 'বকেয়া';

  @override
  String get adjustRentAction => 'ভাড়া সমন্বয় (চার্জ/ছাড়)';

  @override
  String get adjustmentTypeDebit => 'ডেবিট (অতিরিক্ত চার্জ)';

  @override
  String get adjustmentTypeCredit => 'ক্রেডিট (ভাড়া ছাড়)';

  @override
  String get adjustmentAmountLabel => 'সমন্বয়ের পরিমাণ (টাকা)';

  @override
  String get adjustmentReasonLabel => 'বাধ্যতামূলক কারণ / বিবরণ';

  @override
  String get collectPaymentTitle => 'একাধিক দোকান ও মাসের ভাড়া আদায়';

  @override
  String get paymentAmountLabel => 'প্রাপ্ত মোট অর্থ (টাকা)';

  @override
  String get paymentMethodLabel => 'পেমেন্ট মাধ্যম';

  @override
  String get methodCash => 'নগদ (Cash)';

  @override
  String get methodBank => 'ব্যাংক ট্রান্সফার';

  @override
  String get methodMfs => 'মোবাইল ব্যাংকিং (বিকাশ/নগদ)';

  @override
  String get proposeOldestDueAction => 'পুরাতন বকেয়া অনুযায়ী প্রস্তাব দেখুন';

  @override
  String get proposalReviewBanner =>
      'প্রস্তাবিত বকেয়া বরাদ্দ যাচাই করুন — মালিকের নিশ্চিতকরণ ছাড়া পোস্ট হয় না';

  @override
  String get rentAllocatedTotalLabel => 'মোট ভাড়া বাবদ বরাদ্দ';

  @override
  String get excessToTenantCreditLabel =>
      'অতিরিক্ত অর্থ → ভাড়াটিয়া ক্রেডিট (স্বয়ংক্রিয়)';

  @override
  String get confirmAndPostPaymentAction => 'নিশ্চিত করুন ও পেমেন্ট পোস্ট করুন';

  @override
  String get receiptDialogTitle => 'ভাড়া আদায়ের রসিদ পোস্ট হয়েছে';

  @override
  String get receiptNumberLabel => 'রসিদ নম্বর';

  @override
  String get reportAccrualTitle =>
      'মাসভিত্তিক ভাড়ার হিসাব (Billing Period Accrual)';

  @override
  String get reportAccrualSubtitle =>
      'ভাড়ার মাস অনুযায়ী হিসাব (যেমন অক্টোবরের ভাড়া নভেম্বরে আদায় হলেও তা অক্টোবর মাসের ভাড়ায় নিষ্পত্তি দেখায়)।';

  @override
  String get reportCashTitle =>
      'পেমেন্টের তারিখ অনুযায়ী নগদ আদায় (Cash Collection)';

  @override
  String get reportCashSubtitle =>
      'নির্বাচিত তারিখে প্রাপ্ত নগদ অর্থ (ফেরতযোগ্য জামানত ভাড়া আয়ের অন্তর্ভুক্ত নয়)।';

  @override
  String get cashReceivedTotalLabel => 'মোট প্রাপ্ত নগদ অর্থ';

  @override
  String get reconciliationVerifiedBanner =>
      'সমন্বিত হিসাব: প্রাপ্ত নগদ = ভাড়া বরাদ্দ + সৃষ্ট ভাড়াটিয়া ক্রেডিট';

  @override
  String get monthlyAccrualBreakdownTitle => 'মাসওয়ারী ভাড়ার বিবরণী';

  @override
  String get noticeSheetTitle => 'চুক্তি সমাপ্তি / নবায়ন না করার নোটিশ দিন';

  @override
  String get noticeTypeLabel => 'নোটিশের ধরন';

  @override
  String get noticeTypeNonRenewal => 'মেয়াদ শেষে নবায়ন না করা (Non-Renewal)';

  @override
  String get noticeTypeEarlyTermination =>
      'মেয়াদের পূর্বে চুক্তি সমাপ্তির আবেদন';

  @override
  String get noticeReasonLabel => 'কারণ / মন্তব্য';

  @override
  String get selectShopsToVacateLabel =>
      'নোটিশের আওতাভুক্ত দোকান নির্বাচন করুন';

  @override
  String get confirmSubmitNoticeAction => 'নিশ্চিত করুন ও নোটিশ জমা দিন';

  @override
  String get submittedNoticesTimelineTitle => 'জমাকৃত নোটিশ ও অবস্থার টাইমলাইন';

  @override
  String get requestWithdrawalAction => 'নোটিশ প্রত্যাহারের আবেদন';

  @override
  String get errorNotAuthorized => 'এই কাজটি করার অনুমতি আপনার নেই।';

  @override
  String get errorTenantNotLinked =>
      'আপনার অ্যাকাউন্ট এখনো কোনো যাচাইকৃত ভাড়াটিয়া তথ্যের সাথে যুক্ত হয়নি।';

  @override
  String get errorAgreementNotFound => 'চুক্তিটি খুঁজে পাওয়া যায়নি।';

  @override
  String get errorAgreementNotActive => 'চুক্তিটি বর্তমানে সক্রিয় নয়।';

  @override
  String get errorAgreementNumberExists =>
      'এই নম্বরের একটি চুক্তি ইতিমধ্যে বিদ্যমান রয়েছে।';

  @override
  String get errorUnitNotAvailable =>
      'নির্বাচিত দোকানটি উক্ত সময়ের জন্য ইতিমধ্যে ভাড়াকৃত বা সংরক্ষিত।';

  @override
  String get errorObligationNotFound => 'ভাড়ার এন্ট্রিটি খুঁজে পাওয়া যায়নি।';

  @override
  String get errorAdjustmentWouldNegateRent =>
      'এই সমন্বয়ের ফলে প্রদেয় ভাড়া শূন্যের নিচে বা ইতিমধ্যে পরিশোধিত পরিমাণের নিচে নেমে যাবে।';

  @override
  String get errorAllocationExceedsOutstanding =>
      'বরাদ্দকৃত অর্থ বকেয়া ভাড়ার চেয়ে বেশি হতে পারবে না।';

  @override
  String get errorPaymentAllocationMismatch =>
      'ভাড়া বরাদ্দের যোগফল প্রাপ্ত অর্থের চেয়ে বেশি হতে পারবে না।';

  @override
  String get errorPaymentCreditAlreadyUsed =>
      'এই পেমেন্টের অতিরিক্ত অর্থ থেকে সৃষ্ট ক্রেডিট ব্যবহৃত হওয়ায় পেমেন্টটি বাতিল করা যাবে না।';

  @override
  String get errorInsufficientSecurityDeposit =>
      'এই চুক্তিতে পর্যাপ্ত জামানত স্থিতি নেই।';

  @override
  String get errorInsufficientPrepaidRent =>
      'পর্যাপ্ত অগ্রিম ভাড়া স্থিতি নেই।';

  @override
  String get errorInsufficientTenantCredit =>
      'পর্যাপ্ত ভাড়াটিয়া ক্রেডিট স্থিতি নেই।';

  @override
  String get errorDepositApplicationNotAuthorized =>
      'জামানত থেকে ভাড়া সমন্বয়ের জন্য চুক্তির অনুমতি, মালিকের নিশ্চিতকরণ এবং কারণ উল্লেখ আবশ্যক।';

  @override
  String get errorNoticeNotAllowed =>
      'স্বাক্ষরিত চুক্তির শর্তানুযায়ী মেয়াদের পূর্বে চুক্তি সমাপ্তির অনুমতি নেই।';

  @override
  String get errorNoticePeriodNotMet =>
      'প্রস্তাবিত তারিখটি নির্ধারিত ক্যালেন্ডার মাসের নোটিশ মেয়াদ পূরণ করে না।';

  @override
  String get errorPartialTerminationNotAllowed =>
      'এই চুক্তিতে আংশিক দোকান ছেড়ে দেওয়ার অনুমতি নেই।';

  @override
  String get errorActiveNoticeExists =>
      'নির্বাচিত দোকানের জন্য ইতিমধ্যে একটি সক্রিয় নোটিশ রয়েছে।';

  @override
  String get errorPostMoveOutSettled =>
      'দোকান ছাড়ার পরবর্তী কোনো মাসে ভাড়া পরিশোধিত থাকলে মুভ-আউট সম্পন্ন করা যাবে না।';

  @override
  String get errorIdempotencyConflict =>
      'এই কী ব্যবহার করে ভিন্ন তথ্যের আরেকটি অনুরোধ ইতিমধ্যে পাঠানো হয়েছে।';

  @override
  String get errorValidation => 'প্রদত্ত তথ্য যাচাই করে আবার চেষ্টা করুন।';

  @override
  String get errorGeneric => 'একটি ত্রুটি ঘটেছে। অনুগ্রহ করে আবার চেষ্টা করুন।';
}
