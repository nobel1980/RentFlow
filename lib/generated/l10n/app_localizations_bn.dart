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
