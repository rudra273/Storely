// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navHome => 'Home';

  @override
  String get navProducts => 'Products';

  @override
  String get navBills => 'Bills';

  @override
  String get navStore => 'Store';

  @override
  String get navScan => 'Scan';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get scanAndBill => 'Scan & Bill';

  @override
  String get addProduct => 'Add Product';

  @override
  String get labels => 'Labels';

  @override
  String get reports => 'Reports';

  @override
  String get workspace => 'Workspace';

  @override
  String get customers => 'Customers';

  @override
  String get suppliers => 'Suppliers';

  @override
  String get pricing => 'Pricing';

  @override
  String get gstAndRates => 'GST & rates';

  @override
  String get expenses => 'Expenses';

  @override
  String get rentSalary => 'Rent, salary';

  @override
  String get unpaidBills => 'Unpaid Bills';

  @override
  String get needsAttention => 'Needs Attention';

  @override
  String get viewAll => 'View All →';

  @override
  String get billsToday => 'Bills Today';

  @override
  String get products => 'Products';

  @override
  String get searchItems => 'Search items...';

  @override
  String get searchEverything => 'Search products, bills, customers...';

  @override
  String get notifications => 'Notifications';

  @override
  String savedCount(int count) {
    return '$count saved';
  }

  @override
  String get searchProducts => 'Search products';

  @override
  String get addItems => 'Add items';

  @override
  String get completeBill => 'Complete bill';

  @override
  String get holdBill => 'Hold bill';

  @override
  String get discard => 'Discard';

  @override
  String get discardBillQ => 'Discard this bill?';

  @override
  String get undo => 'Undo';

  @override
  String get customerName => 'Customer name';

  @override
  String get phoneOptional => 'Phone number (optional)';

  @override
  String get discountPercent => 'Discount percentage';

  @override
  String get amountReceived => 'Amount received';

  @override
  String get generateBill => 'Generate Bill';

  @override
  String get grandTotal => 'Grand Total';

  @override
  String get items => 'Items';

  @override
  String get received => 'Received';

  @override
  String get balance => 'Balance';

  @override
  String get roundOff => 'Round off';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get txnIdOptional => 'Transaction ID (optional)';

  @override
  String get billCreated => 'Bill Created!';

  @override
  String get printReceipt => 'Print receipt';

  @override
  String get sharePdf => 'Share PDF (WhatsApp, print…)';

  @override
  String get newBill => 'New Bill';

  @override
  String get createBill => 'Create Bill';

  @override
  String get noBillsYet => 'No bills yet';

  @override
  String get createFirstBill => 'Create your first bill to get started';

  @override
  String get searchBills => 'Search bills...';

  @override
  String get active => 'Active';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get duplicateAsNew => 'Duplicate as New';

  @override
  String get history => 'History';

  @override
  String get cancel => 'Cancel';

  @override
  String get edit => 'Edit';

  @override
  String get returnItems => 'Return';

  @override
  String get markPaid => 'Mark Paid';

  @override
  String get markUnpaid => 'Mark Unpaid';

  @override
  String get recordPayment => 'Record Payment';

  @override
  String get whatsapp => 'WhatsApp';

  @override
  String get print => 'Print';

  @override
  String get share => 'Share';

  @override
  String get viewProfit => 'View Profit';

  @override
  String get paid => 'Paid';

  @override
  String get partial => 'Partial';

  @override
  String get unpaid => 'Unpaid';

  @override
  String get cash => 'Cash';

  @override
  String get online => 'Online';

  @override
  String get creditNote => 'Credit note';

  @override
  String get waitingToSync => 'Saved on this phone · waiting to sync';

  @override
  String get quickAddProduct => 'Quick add product';

  @override
  String get productNameReq => 'Product name *';

  @override
  String get sellingPriceReq => 'Selling price *';

  @override
  String get unit => 'Unit';

  @override
  String get openingStock => 'Opening stock';

  @override
  String get notTracked => 'Not tracked';

  @override
  String get costPrice => 'Cost price';

  @override
  String get optional => 'Optional';

  @override
  String get barcodeOptional => 'Barcode (optional)';

  @override
  String get scanBarcode => 'Scan barcode';

  @override
  String get trackStock => 'Track stock';

  @override
  String get trackStockHint => 'Turn off for services and loose items';

  @override
  String get save => 'Save';

  @override
  String get saveAndAddAnother => 'Save & add another';

  @override
  String get fullPurchaseEntry => 'Full purchase entry (supplier, import)';

  @override
  String get lowStock => 'Low';

  @override
  String get outOfStock => 'Out';

  @override
  String get more => 'More';

  @override
  String get adjustStock => 'Adjust stock';

  @override
  String get stockHistory => 'Stock history';

  @override
  String get delete => 'Delete';

  @override
  String get stockNotTracked => 'Stock not tracked';

  @override
  String get noProductsYet => 'No products yet';

  @override
  String get addProductsHint =>
      'Add items one by one, or enter a purchase to import a list';

  @override
  String get newPurchaseImport => 'New purchase / import';

  @override
  String get addProductLower => 'Add product';

  @override
  String get language => 'Language';

  @override
  String get chooseLanguage => 'Choose language';

  @override
  String get todaysBookedSales => 'TODAY\'S BOOKED SALES';

  @override
  String get noBillsToday => 'No bills yet today';

  @override
  String collectedBills(String amount, int count) {
    return '$amount collected, $count bills created';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get allBillsPaid => 'All bills are paid!';

  @override
  String get allStockedUp => 'All stocked up!';

  @override
  String get walkIn => 'Walk-in';

  @override
  String get search => 'Search';

  @override
  String get frequentlySold => 'Frequently sold first';

  @override
  String get manualBill => 'Manual Bill';

  @override
  String get duplicateBill => 'Duplicate Bill';

  @override
  String get clear => 'Clear';

  @override
  String get total => 'Total';

  @override
  String get bill => 'Bill';

  @override
  String get keepBilling => 'Keep Billing';

  @override
  String get noItemsYet => 'No items added yet';

  @override
  String get itemAdded => 'Item added!';

  @override
  String get addProductsFirst => 'Add products before manual billing';

  @override
  String get noMatchingProducts => 'No matching products';

  @override
  String get pointCamera => 'Point camera at product QR code';

  @override
  String get heldBills => 'Held bills';

  @override
  String get noHeldBills => 'No held bills';

  @override
  String get done => 'Done';

  @override
  String get paidFull => 'Paid full';

  @override
  String get searchItemsBtn => 'Search items';

  @override
  String heldCount(int count) {
    return 'Held ($count)';
  }

  @override
  String itemsInBill(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items in bill',
      one: '1 item in bill',
    );
    return '$_temp0';
  }

  @override
  String get customerGstin => 'Customer GSTIN';

  @override
  String get legalName => 'Legal business name';

  @override
  String get tradeNameOpt => 'Trade name (optional)';

  @override
  String get businessAddress => 'Business address';

  @override
  String get placeOfSupplyCode => 'Place of supply state code';

  @override
  String get welcomeTitle => 'Welcome to Storely';

  @override
  String get welcomeChoice => 'Start a new shop or join an existing cloud shop';

  @override
  String get welcomeCreate => 'Add your shop name to get started';

  @override
  String get welcomeJoin => 'Sign in to join a shop you were added to';

  @override
  String get startFresh => 'Start Fresh';

  @override
  String get joinExistingShop => 'Join Existing Shop';

  @override
  String get shopName => 'Shop Name';

  @override
  String get required => 'Required';

  @override
  String get continueLabel => 'Continue';

  @override
  String get back => 'Back';

  @override
  String get addSampleProducts => 'Add a few sample products';

  @override
  String get sampleProductsHint =>
      'Try billing straight away. Delete them any time.';
}
