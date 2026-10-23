import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

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
    Locale('en'),
    Locale('hi'),
  ];

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get navProducts;

  /// No description provided for @navBills.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get navBills;

  /// No description provided for @navStore.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get navStore;

  /// No description provided for @navScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get navScan;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @scanAndBill.
  ///
  /// In en, this message translates to:
  /// **'Scan & Bill'**
  String get scanAndBill;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get addProduct;

  /// No description provided for @labels.
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get labels;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @workspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get workspace;

  /// No description provided for @customers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customers;

  /// No description provided for @suppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get suppliers;

  /// No description provided for @pricing.
  ///
  /// In en, this message translates to:
  /// **'Pricing'**
  String get pricing;

  /// No description provided for @gstAndRates.
  ///
  /// In en, this message translates to:
  /// **'GST & rates'**
  String get gstAndRates;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @rentSalary.
  ///
  /// In en, this message translates to:
  /// **'Rent, salary'**
  String get rentSalary;

  /// No description provided for @unpaidBills.
  ///
  /// In en, this message translates to:
  /// **'Unpaid Bills'**
  String get unpaidBills;

  /// No description provided for @needsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs Attention'**
  String get needsAttention;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All →'**
  String get viewAll;

  /// No description provided for @billsToday.
  ///
  /// In en, this message translates to:
  /// **'Bills Today'**
  String get billsToday;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @searchItems.
  ///
  /// In en, this message translates to:
  /// **'Search items...'**
  String get searchItems;

  /// No description provided for @searchEverything.
  ///
  /// In en, this message translates to:
  /// **'Search products, bills, customers...'**
  String get searchEverything;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @savedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} saved'**
  String savedCount(int count);

  /// No description provided for @searchProducts.
  ///
  /// In en, this message translates to:
  /// **'Search products'**
  String get searchProducts;

  /// No description provided for @addItems.
  ///
  /// In en, this message translates to:
  /// **'Add items'**
  String get addItems;

  /// No description provided for @completeBill.
  ///
  /// In en, this message translates to:
  /// **'Complete bill'**
  String get completeBill;

  /// No description provided for @holdBill.
  ///
  /// In en, this message translates to:
  /// **'Hold bill'**
  String get holdBill;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @discardBillQ.
  ///
  /// In en, this message translates to:
  /// **'Discard this bill?'**
  String get discardBillQ;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @customerName.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get customerName;

  /// No description provided for @phoneOptional.
  ///
  /// In en, this message translates to:
  /// **'Phone number (optional)'**
  String get phoneOptional;

  /// No description provided for @discountPercent.
  ///
  /// In en, this message translates to:
  /// **'Discount percentage'**
  String get discountPercent;

  /// No description provided for @amountReceived.
  ///
  /// In en, this message translates to:
  /// **'Amount received'**
  String get amountReceived;

  /// No description provided for @generateBill.
  ///
  /// In en, this message translates to:
  /// **'Generate Bill'**
  String get generateBill;

  /// No description provided for @grandTotal.
  ///
  /// In en, this message translates to:
  /// **'Grand Total'**
  String get grandTotal;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get items;

  /// No description provided for @received.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get received;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @roundOff.
  ///
  /// In en, this message translates to:
  /// **'Round off'**
  String get roundOff;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @txnIdOptional.
  ///
  /// In en, this message translates to:
  /// **'Transaction ID (optional)'**
  String get txnIdOptional;

  /// No description provided for @billCreated.
  ///
  /// In en, this message translates to:
  /// **'Bill Created!'**
  String get billCreated;

  /// No description provided for @printReceipt.
  ///
  /// In en, this message translates to:
  /// **'Print receipt'**
  String get printReceipt;

  /// No description provided for @sharePdf.
  ///
  /// In en, this message translates to:
  /// **'Share PDF (WhatsApp, print…)'**
  String get sharePdf;

  /// No description provided for @newBill.
  ///
  /// In en, this message translates to:
  /// **'New Bill'**
  String get newBill;

  /// No description provided for @createBill.
  ///
  /// In en, this message translates to:
  /// **'Create Bill'**
  String get createBill;

  /// No description provided for @noBillsYet.
  ///
  /// In en, this message translates to:
  /// **'No bills yet'**
  String get noBillsYet;

  /// No description provided for @createFirstBill.
  ///
  /// In en, this message translates to:
  /// **'Create your first bill to get started'**
  String get createFirstBill;

  /// No description provided for @searchBills.
  ///
  /// In en, this message translates to:
  /// **'Search bills...'**
  String get searchBills;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @duplicateAsNew.
  ///
  /// In en, this message translates to:
  /// **'Duplicate as New'**
  String get duplicateAsNew;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @returnItems.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get returnItems;

  /// No description provided for @markPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark Paid'**
  String get markPaid;

  /// No description provided for @markUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Mark Unpaid'**
  String get markUnpaid;

  /// No description provided for @recordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get recordPayment;

  /// No description provided for @whatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get whatsapp;

  /// No description provided for @print.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get print;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @viewProfit.
  ///
  /// In en, this message translates to:
  /// **'View Profit'**
  String get viewProfit;

  /// No description provided for @paid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid;

  /// No description provided for @partial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get partial;

  /// No description provided for @unpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get unpaid;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cash;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @creditNote.
  ///
  /// In en, this message translates to:
  /// **'Credit note'**
  String get creditNote;

  /// No description provided for @waitingToSync.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone · waiting to sync'**
  String get waitingToSync;

  /// No description provided for @quickAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Quick add product'**
  String get quickAddProduct;

  /// No description provided for @productNameReq.
  ///
  /// In en, this message translates to:
  /// **'Product name *'**
  String get productNameReq;

  /// No description provided for @sellingPriceReq.
  ///
  /// In en, this message translates to:
  /// **'Selling price *'**
  String get sellingPriceReq;

  /// No description provided for @unit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unit;

  /// No description provided for @openingStock.
  ///
  /// In en, this message translates to:
  /// **'Opening stock'**
  String get openingStock;

  /// No description provided for @notTracked.
  ///
  /// In en, this message translates to:
  /// **'Not tracked'**
  String get notTracked;

  /// No description provided for @costPrice.
  ///
  /// In en, this message translates to:
  /// **'Cost price'**
  String get costPrice;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @barcodeOptional.
  ///
  /// In en, this message translates to:
  /// **'Barcode (optional)'**
  String get barcodeOptional;

  /// No description provided for @scanBarcode.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get scanBarcode;

  /// No description provided for @trackStock.
  ///
  /// In en, this message translates to:
  /// **'Track stock'**
  String get trackStock;

  /// No description provided for @trackStockHint.
  ///
  /// In en, this message translates to:
  /// **'Turn off for services and loose items'**
  String get trackStockHint;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveAndAddAnother.
  ///
  /// In en, this message translates to:
  /// **'Save & add another'**
  String get saveAndAddAnother;

  /// No description provided for @fullPurchaseEntry.
  ///
  /// In en, this message translates to:
  /// **'Full purchase entry (supplier, import)'**
  String get fullPurchaseEntry;

  /// No description provided for @lowStock.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get lowStock;

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get outOfStock;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @adjustStock.
  ///
  /// In en, this message translates to:
  /// **'Adjust stock'**
  String get adjustStock;

  /// No description provided for @stockHistory.
  ///
  /// In en, this message translates to:
  /// **'Stock history'**
  String get stockHistory;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @stockNotTracked.
  ///
  /// In en, this message translates to:
  /// **'Stock not tracked'**
  String get stockNotTracked;

  /// No description provided for @noProductsYet.
  ///
  /// In en, this message translates to:
  /// **'No products yet'**
  String get noProductsYet;

  /// No description provided for @addProductsHint.
  ///
  /// In en, this message translates to:
  /// **'Add items one by one, or enter a purchase to import a list'**
  String get addProductsHint;

  /// No description provided for @newPurchaseImport.
  ///
  /// In en, this message translates to:
  /// **'New purchase / import'**
  String get newPurchaseImport;

  /// No description provided for @addProductLower.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get addProductLower;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get chooseLanguage;

  /// No description provided for @todaysBookedSales.
  ///
  /// In en, this message translates to:
  /// **'TODAY\'S BOOKED SALES'**
  String get todaysBookedSales;

  /// No description provided for @noBillsToday.
  ///
  /// In en, this message translates to:
  /// **'No bills yet today'**
  String get noBillsToday;

  /// No description provided for @collectedBills.
  ///
  /// In en, this message translates to:
  /// **'{amount} collected, {count} bills created'**
  String collectedBills(String amount, int count);

  /// No description provided for @itemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String itemCount(int count);

  /// No description provided for @allBillsPaid.
  ///
  /// In en, this message translates to:
  /// **'All bills are paid!'**
  String get allBillsPaid;

  /// No description provided for @allStockedUp.
  ///
  /// In en, this message translates to:
  /// **'All stocked up!'**
  String get allStockedUp;

  /// No description provided for @walkIn.
  ///
  /// In en, this message translates to:
  /// **'Walk-in'**
  String get walkIn;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @frequentlySold.
  ///
  /// In en, this message translates to:
  /// **'Frequently sold first'**
  String get frequentlySold;

  /// No description provided for @manualBill.
  ///
  /// In en, this message translates to:
  /// **'Manual Bill'**
  String get manualBill;

  /// No description provided for @duplicateBill.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Bill'**
  String get duplicateBill;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @bill.
  ///
  /// In en, this message translates to:
  /// **'Bill'**
  String get bill;

  /// No description provided for @keepBilling.
  ///
  /// In en, this message translates to:
  /// **'Keep Billing'**
  String get keepBilling;

  /// No description provided for @noItemsYet.
  ///
  /// In en, this message translates to:
  /// **'No items added yet'**
  String get noItemsYet;

  /// No description provided for @itemAdded.
  ///
  /// In en, this message translates to:
  /// **'Item added!'**
  String get itemAdded;

  /// No description provided for @addProductsFirst.
  ///
  /// In en, this message translates to:
  /// **'Add products before manual billing'**
  String get addProductsFirst;

  /// No description provided for @noMatchingProducts.
  ///
  /// In en, this message translates to:
  /// **'No matching products'**
  String get noMatchingProducts;

  /// No description provided for @pointCamera.
  ///
  /// In en, this message translates to:
  /// **'Point camera at product QR code'**
  String get pointCamera;

  /// No description provided for @heldBills.
  ///
  /// In en, this message translates to:
  /// **'Held bills'**
  String get heldBills;

  /// No description provided for @noHeldBills.
  ///
  /// In en, this message translates to:
  /// **'No held bills'**
  String get noHeldBills;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @paidFull.
  ///
  /// In en, this message translates to:
  /// **'Paid full'**
  String get paidFull;

  /// No description provided for @searchItemsBtn.
  ///
  /// In en, this message translates to:
  /// **'Search items'**
  String get searchItemsBtn;

  /// No description provided for @heldCount.
  ///
  /// In en, this message translates to:
  /// **'Held ({count})'**
  String heldCount(int count);

  /// No description provided for @itemsInBill.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item in bill} other{{count} items in bill}}'**
  String itemsInBill(int count);

  /// No description provided for @customerGstin.
  ///
  /// In en, this message translates to:
  /// **'Customer GSTIN'**
  String get customerGstin;

  /// No description provided for @legalName.
  ///
  /// In en, this message translates to:
  /// **'Legal business name'**
  String get legalName;

  /// No description provided for @tradeNameOpt.
  ///
  /// In en, this message translates to:
  /// **'Trade name (optional)'**
  String get tradeNameOpt;

  /// No description provided for @businessAddress.
  ///
  /// In en, this message translates to:
  /// **'Business address'**
  String get businessAddress;

  /// No description provided for @placeOfSupplyCode.
  ///
  /// In en, this message translates to:
  /// **'Place of supply state code'**
  String get placeOfSupplyCode;
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
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
