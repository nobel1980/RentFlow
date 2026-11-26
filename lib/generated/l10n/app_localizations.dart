import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'RentFlow'**
  String get appTitle;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navShops.
  ///
  /// In en, this message translates to:
  /// **'Shops'**
  String get navShops;

  /// No description provided for @navTenants.
  ///
  /// In en, this message translates to:
  /// **'Tenants'**
  String get navTenants;

  /// No description provided for @navPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get navPayments;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navMyShops.
  ///
  /// In en, this message translates to:
  /// **'My Shops'**
  String get navMyShops;

  /// No description provided for @navMyRent.
  ///
  /// In en, this message translates to:
  /// **'Rent & Dues'**
  String get navMyRent;

  /// No description provided for @navMyAgreement.
  ///
  /// In en, this message translates to:
  /// **'Agreement & Notice'**
  String get navMyAgreement;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @roleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwner;

  /// No description provided for @roleTenant.
  ///
  /// In en, this message translates to:
  /// **'Tenant'**
  String get roleTenant;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @languageBangla.
  ///
  /// In en, this message translates to:
  /// **'বাংলা (Bangla)'**
  String get languageBangla;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @switchRolePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview Tenant Portal'**
  String get switchRolePreview;

  /// No description provided for @switchToOwnerPreview.
  ///
  /// In en, this message translates to:
  /// **'Back to Owner View'**
  String get switchToOwnerPreview;

  /// No description provided for @fundSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Separate Tenant Fund Balances'**
  String get fundSectionTitle;

  /// No description provided for @fundSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Refundable deposit, prepaid rent, and excess payment credit are tracked in separate ledgers and never combined.'**
  String get fundSectionSubtitle;

  /// No description provided for @securityDepositTitle.
  ///
  /// In en, this message translates to:
  /// **'Security Deposit'**
  String get securityDepositTitle;

  /// No description provided for @securityDepositCaption.
  ///
  /// In en, this message translates to:
  /// **'Refundable security deposit (not rent income)'**
  String get securityDepositCaption;

  /// No description provided for @prepaidRentTitle.
  ///
  /// In en, this message translates to:
  /// **'Prepaid Advance Rent'**
  String get prepaidRentTitle;

  /// No description provided for @prepaidRentCaption.
  ///
  /// In en, this message translates to:
  /// **'Explicitly received for future billing periods'**
  String get prepaidRentCaption;

  /// No description provided for @tenantCreditTitle.
  ///
  /// In en, this message translates to:
  /// **'Tenant Credit'**
  String get tenantCreditTitle;

  /// No description provided for @tenantCreditCaption.
  ///
  /// In en, this message translates to:
  /// **'Unallocated excess payment held for future rent'**
  String get tenantCreditCaption;

  /// No description provided for @statusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get statusPaid;

  /// No description provided for @statusPartiallyPaid.
  ///
  /// In en, this message translates to:
  /// **'Partially Paid'**
  String get statusPartiallyPaid;

  /// No description provided for @statusDue.
  ///
  /// In en, this message translates to:
  /// **'Due Today'**
  String get statusDue;

  /// No description provided for @statusOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get statusOverdue;

  /// No description provided for @statusUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get statusUpcoming;

  /// No description provided for @statusOccupied.
  ///
  /// In en, this message translates to:
  /// **'Occupied'**
  String get statusOccupied;

  /// No description provided for @statusVacant.
  ///
  /// In en, this message translates to:
  /// **'Vacant'**
  String get statusVacant;

  /// No description provided for @statusMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get statusMaintenance;

  /// No description provided for @billingOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Current Month Rent Accrual'**
  String get billingOverviewTitle;

  /// No description provided for @expectedRentLabel.
  ///
  /// In en, this message translates to:
  /// **'Expected Rent'**
  String get expectedRentLabel;

  /// No description provided for @collectedAllocatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Allocated Rent Settled'**
  String get collectedAllocatedLabel;

  /// No description provided for @outstandingRentLabel.
  ///
  /// In en, this message translates to:
  /// **'Outstanding Balance'**
  String get outstandingRentLabel;

  /// No description provided for @overdueRentLabel.
  ///
  /// In en, this message translates to:
  /// **'Overdue Balance'**
  String get overdueRentLabel;

  /// No description provided for @occupancyOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Shop Occupancy (No Unit Cap)'**
  String get occupancyOverviewTitle;

  /// No description provided for @totalUnitsLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Shops'**
  String get totalUnitsLabel;

  /// No description provided for @occupiedUnitsLabel.
  ///
  /// In en, this message translates to:
  /// **'Occupied'**
  String get occupiedUnitsLabel;

  /// No description provided for @vacantUnitsLabel.
  ///
  /// In en, this message translates to:
  /// **'Vacant'**
  String get vacantUnitsLabel;

  /// No description provided for @noticeSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Termination & Non-Renewal Notice Policy'**
  String get noticeSectionTitle;

  /// No description provided for @noticePeriodMonths.
  ///
  /// In en, this message translates to:
  /// **'{months}-Calendar-Month Notice Period'**
  String noticePeriodMonths(int months);

  /// No description provided for @submitNoticeAction.
  ///
  /// In en, this message translates to:
  /// **'Submit Non-Renewal / Termination Notice'**
  String get submitNoticeAction;

  /// No description provided for @recordPaymentAction.
  ///
  /// In en, this message translates to:
  /// **'Record Rent Payment'**
  String get recordPaymentAction;

  /// No description provided for @retryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryAction;

  /// No description provided for @emptyStateTitle.
  ///
  /// In en, this message translates to:
  /// **'No records found'**
  String get emptyStateTitle;

  /// No description provided for @loadingLabel.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loadingLabel;

  /// No description provided for @errorNotAuthorized.
  ///
  /// In en, this message translates to:
  /// **'You are not authorized to perform this action.'**
  String get errorNotAuthorized;

  /// No description provided for @errorTenantNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Your tenant account is not linked to a verified tenancy record yet.'**
  String get errorTenantNotLinked;

  /// No description provided for @errorAgreementNotFound.
  ///
  /// In en, this message translates to:
  /// **'Agreement was not found.'**
  String get errorAgreementNotFound;

  /// No description provided for @errorAgreementNotActive.
  ///
  /// In en, this message translates to:
  /// **'Agreement is not currently active.'**
  String get errorAgreementNotActive;

  /// No description provided for @errorAgreementNumberExists.
  ///
  /// In en, this message translates to:
  /// **'An agreement with this reference number already exists.'**
  String get errorAgreementNumberExists;

  /// No description provided for @errorUnitNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Selected shop is already occupied or reserved for an overlapping date range.'**
  String get errorUnitNotAvailable;

  /// No description provided for @errorObligationNotFound.
  ///
  /// In en, this message translates to:
  /// **'Rent obligation was not found.'**
  String get errorObligationNotFound;

  /// No description provided for @errorAdjustmentWouldNegateRent.
  ///
  /// In en, this message translates to:
  /// **'This adjustment would reduce payable rent below zero or below the already-settled amount.'**
  String get errorAdjustmentWouldNegateRent;

  /// No description provided for @errorAllocationExceedsOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Allocation exceeds the current outstanding balance for one or more obligations.'**
  String get errorAllocationExceedsOutstanding;

  /// No description provided for @errorPaymentAllocationMismatch.
  ///
  /// In en, this message translates to:
  /// **'Total rent allocations cannot exceed the received payment amount.'**
  String get errorPaymentAllocationMismatch;

  /// No description provided for @errorPaymentCreditAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'Payment cannot be reversed because the tenant credit created from its excess has already been used.'**
  String get errorPaymentCreditAlreadyUsed;

  /// No description provided for @errorInsufficientSecurityDeposit.
  ///
  /// In en, this message translates to:
  /// **'Amount exceeds the available security deposit balance for this agreement.'**
  String get errorInsufficientSecurityDeposit;

  /// No description provided for @errorInsufficientPrepaidRent.
  ///
  /// In en, this message translates to:
  /// **'Amount exceeds the available prepaid advance rent balance.'**
  String get errorInsufficientPrepaidRent;

  /// No description provided for @errorInsufficientTenantCredit.
  ///
  /// In en, this message translates to:
  /// **'Amount exceeds the available tenant credit balance.'**
  String get errorInsufficientTenantCredit;

  /// No description provided for @errorDepositApplicationNotAuthorized.
  ///
  /// In en, this message translates to:
  /// **'Security deposit application requires agreement permission, owner confirmation, and a recorded reason.'**
  String get errorDepositApplicationNotAuthorized;

  /// No description provided for @errorNoticeNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Early termination is not permitted under the signed agreement terms.'**
  String get errorNoticeNotAllowed;

  /// No description provided for @errorNoticePeriodNotMet.
  ///
  /// In en, this message translates to:
  /// **'Requested date does not meet the required calendar-month notice period.'**
  String get errorNoticePeriodNotMet;

  /// No description provided for @errorPartialTerminationNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Partial shop termination is not permitted under this agreement.'**
  String get errorPartialTerminationNotAllowed;

  /// No description provided for @errorActiveNoticeExists.
  ///
  /// In en, this message translates to:
  /// **'An active termination notice already exists for one or more selected shops.'**
  String get errorActiveNoticeExists;

  /// No description provided for @errorPostMoveOutSettled.
  ///
  /// In en, this message translates to:
  /// **'Cannot complete move-out while a post-move-out billing period has applied payments or credits.'**
  String get errorPostMoveOutSettled;

  /// No description provided for @errorIdempotencyConflict.
  ///
  /// In en, this message translates to:
  /// **'A different request was already submitted with this idempotency key.'**
  String get errorIdempotencyConflict;

  /// No description provided for @errorValidation.
  ///
  /// In en, this message translates to:
  /// **'Please check your inputs and try again.'**
  String get errorValidation;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
