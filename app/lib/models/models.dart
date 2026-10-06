double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();
String? _s(dynamic v) => v?.toString();
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

class AppUser {
  AppUser({
    required this.id,
    required this.username,
    this.fullName,
    required this.role,
    required this.isActive,
    this.createdAt,
    this.lastLoginAt,
  });

  final int id;
  final String username;
  final String? fullName;
  final String role;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  bool get isAdmin => role == 'Admin';
  String get displayName => (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : username;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: _i(j['id']),
        username: j['username'] ?? '',
        fullName: _s(j['fullName']),
        role: j['role'] ?? 'User',
        isActive: j['isActive'] ?? true,
        createdAt: _dt(j['createdAt']),
        lastLoginAt: _dt(j['lastLoginAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'fullName': fullName,
        'role': role,
        'isActive': isActive,
        'createdAt': createdAt?.toIso8601String(),
        'lastLoginAt': lastLoginAt?.toIso8601String(),
      };
}

class NamedItem {
  NamedItem(this.id, this.name);
  final String id;
  final String name;
  factory NamedItem.fromJson(Map<String, dynamic> j) => NamedItem(_s(j['id']) ?? '', j['name'] ?? '');
}

class ServiceItem {
  ServiceItem({required this.id, required this.name, this.code, this.unit, this.production = 0, this.taxPercent = 0});
  final String id;
  final String name;
  final String? code;
  final String? unit;
  final double production;
  final double taxPercent;

  factory ServiceItem.fromJson(Map<String, dynamic> j) => ServiceItem(
        id: _s(j['id']) ?? '',
        name: j['name'] ?? '',
        code: _s(j['code']),
        unit: _s(j['unit']),
        production: _d(j['production']),
        taxPercent: _d(j['taxPercent']),
      );
}

class InvoiceDefaults {
  InvoiceDefaults({required this.taxCode, required this.templateCode, required this.invoiceSeries});
  final String taxCode;
  final String templateCode;
  final String invoiceSeries;

  factory InvoiceDefaults.fromJson(Map<String, dynamic> j) => InvoiceDefaults(
        taxCode: j['taxCode'] ?? '',
        templateCode: j['templateCode'] ?? '',
        invoiceSeries: j['invoiceSeries'] ?? '',
      );
}

class OrderItem {
  OrderItem({
    required this.serviceId,
    required this.serviceName,
    required this.quantity,
    this.promotionQuantity = 0,
    required this.unitPrice,
  });

  String serviceId;
  String serviceName;
  int quantity;
  int promotionQuantity;
  double unitPrice;

  int get actualQuantity => quantity - promotionQuantity;
  double get total => actualQuantity * unitPrice;

  OrderItem copy() => OrderItem(
        serviceId: serviceId,
        serviceName: serviceName,
        quantity: quantity,
        promotionQuantity: promotionQuantity,
        unitPrice: unitPrice,
      );

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        serviceId: _s(j['serviceId']) ?? '',
        serviceName: j['serviceName'] ?? '',
        quantity: _i(j['quantity']),
        promotionQuantity: _i(j['promotionQuantity']),
        unitPrice: _d(j['unitPrice']),
      );

  Map<String, dynamic> toJson() => {
        'serviceId': serviceId,
        'serviceName': serviceName,
        'quantity': quantity,
        'promotionQuantity': promotionQuantity,
        'unitPrice': unitPrice,
      };
}

class PaymentRecord {
  PaymentRecord({required this.cash, required this.transfer, this.date});
  final double cash;
  final double transfer;
  final DateTime? date;
}

class OrderSummary {
  OrderSummary({
    required this.id,
    required this.customerName,
    this.shopName,
    this.customerPhone,
    this.customerAddress,
    this.employeeNames,
    required this.items,
    required this.totalPrice,
    required this.cashAmount,
    required this.transferAmount,
    this.createdAt,
    this.paymentStatus,
    this.deliveryStatus,
    required this.isDraft,
    this.invoiceNoViettel,
    this.dateInvViettel,
    required this.exported,
    this.hoaDonNoiBo,
    this.templateCode,
    required this.isConvertToLiter,
    this.taxCode,
    this.identification,
    this.personalName,
    this.invoiceName,
    this.invoiceAddress,
    this.paymentHistory,
  });

  final String id;
  final String customerName;
  final String? shopName;
  final String? customerPhone;
  final String? customerAddress;
  final String? employeeNames;
  final List<OrderItem> items;
  final double totalPrice;
  final double cashAmount;
  final double transferAmount;
  final DateTime? createdAt;
  final String? paymentStatus;
  final String? deliveryStatus;
  final bool isDraft;
  final String? invoiceNoViettel;
  final String? dateInvViettel;
  final bool exported;
  final String? hoaDonNoiBo;
  final String? templateCode;
  final bool isConvertToLiter;
  final String? taxCode;
  final String? identification;
  final String? personalName;
  final String? invoiceName;
  final String? invoiceAddress;
  final String? paymentHistory;

  String get displayName => (shopName?.isNotEmpty ?? false) ? shopName! : customerName;
  bool get hasViettelInvoice => invoiceNoViettel?.trim().isNotEmpty ?? false;
  List<String> get viettelInvoiceNos =>
      (invoiceNoViettel ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  /// Loại người mua theo cùng quy tắc với backend: MST → công ty, CCCD → cá nhân, còn lại → người tiêu dùng.
  String get buyerKind {
    if (taxCode?.isNotEmpty ?? false) return 'company';
    if (identification?.isNotEmpty ?? false) return 'personal';
    return 'consumer';
  }

  factory OrderSummary.fromJson(Map<String, dynamic> j) => OrderSummary(
        id: _s(j['id']) ?? '',
        customerName: j['customerName'] ?? '',
        shopName: _s(j['shopName']),
        customerPhone: _s(j['customerPhone']),
        customerAddress: _s(j['customerAddress']),
        employeeNames: _s(j['employeeNames']),
        items: ((j['items'] as List?) ?? []).map((e) => OrderItem.fromJson(e)).toList(),
        totalPrice: _d(j['totalPrice']),
        cashAmount: _d(j['cashAmount']),
        transferAmount: _d(j['transferAmount']),
        createdAt: _dt(j['createdAt']),
        paymentStatus: _s(j['paymentStatus']),
        deliveryStatus: _s(j['deliveryStatus']),
        isDraft: j['isDraft'] ?? false,
        invoiceNoViettel: _s(j['invoiceNoViettel']),
        dateInvViettel: _s(j['dateInvViettel']),
        exported: j['exported'] ?? false,
        hoaDonNoiBo: _s(j['hoaDonNoiBo']),
        templateCode: _s(j['templateCode']),
        isConvertToLiter: j['isConvertToLiter'] ?? false,
        taxCode: _s(j['taxCode']),
        identification: _s(j['identification']),
        personalName: _s(j['personalName']),
        invoiceName: _s(j['invoiceName']),
        invoiceAddress: _s(j['invoiceAddress']),
        paymentHistory: _s(j['paymentHistory']),
      );
}

class OrderDetail {
  OrderDetail({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.taxPercent,
    required this.isConvertToLiter,
    required this.autoConvertedCount,
    required this.items,
  });

  final String id;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final double taxPercent;
  final bool isConvertToLiter;
  final int autoConvertedCount;
  final List<OrderItem> items;

  factory OrderDetail.fromJson(Map<String, dynamic> j) => OrderDetail(
        id: _s(j['id']) ?? '',
        customerName: j['customerName'] ?? '',
        customerPhone: j['customerPhone'] ?? '',
        customerAddress: j['customerAddress'] ?? '',
        taxPercent: _d(j['taxPercent']),
        isConvertToLiter: j['isConvertToLiter'] ?? false,
        autoConvertedCount: _i(j['autoConvertedCount']),
        items: ((j['items'] as List?) ?? []).map((e) => OrderItem.fromJson(e)).toList(),
      );
}

class InvoiceLine {
  InvoiceLine.fromJson(Map<String, dynamic> j)
      : lineNumber = _i(j['lineNumber']),
        itemCode = j['itemCode'] ?? '',
        itemName = j['itemName'] ?? '',
        unitName = j['unitName'] ?? '',
        unitPrice = _d(j['unitPrice']),
        quantity = _i(j['quantity']),
        amountWithoutTax = _d(j['amountWithoutTax']),
        taxPercent = _d(j['taxPercent']),
        taxAmount = _d(j['taxAmount']);

  final int lineNumber;
  final String itemCode;
  final String itemName;
  final String unitName;
  final double unitPrice;
  final int quantity;
  final double amountWithoutTax;
  final double taxPercent;
  final double taxAmount;
}

class InvoiceGroup {
  InvoiceGroup.fromJson(Map<String, dynamic> j)
      : taxPercent = _d(j['taxPercent']),
        totalWithoutTax = _d(j['totalWithoutTax']),
        totalTax = _d(j['totalTax']),
        totalWithTax = _d(j['totalWithTax']),
        discountAmount = _d(j['discountAmount']),
        amountInWords = j['amountInWords'] ?? '',
        requestJson = j['requestJson'] ?? '',
        lines = ((j['lines'] as List?) ?? []).map((e) => InvoiceLine.fromJson(e)).toList();

  final double taxPercent;
  final double totalWithoutTax;
  final double totalTax;
  final double totalWithTax;
  final double discountAmount;
  final String amountInWords;
  final String requestJson;
  final List<InvoiceLine> lines;
}

class BuyerPreview {
  BuyerPreview.fromJson(Map<String, dynamic> j)
      : kind = j['kind'] ?? 'unknown',
        buyerName = _s(j['buyerName']),
        buyerLegalName = _s(j['buyerLegalName']),
        taxCode = _s(j['taxCode']),
        idNo = _s(j['idNo']),
        address = _s(j['address']),
        phone = _s(j['phone']);

  final String kind;
  final String? buyerName;
  final String? buyerLegalName;
  final String? taxCode;
  final String? idNo;
  final String? address;
  final String? phone;
}

class InvoicePreview {
  InvoicePreview.fromJson(Map<String, dynamic> j)
      : buyer = BuyerPreview.fromJson(j['buyer'] ?? {}),
        groups = ((j['groups'] as List?) ?? []).map((e) => InvoiceGroup.fromJson(e)).toList(),
        warnings = ((j['warnings'] as List?) ?? []).map((e) => e.toString()).toList(),
        ordersToConvert = _i(j['ordersToConvert']);

  final BuyerPreview buyer;
  final List<InvoiceGroup> groups;
  final List<String> warnings;
  final int ordersToConvert;
}

class CreateInvoiceResult {
  CreateInvoiceResult.fromJson(Map<String, dynamic> j)
      : invoiceNos = ((j['invoiceNos'] as List?) ?? []).map((e) => e.toString()).toList(),
        convertedOrders = _i(j['convertedOrders']),
        warnings = ((j['warnings'] as List?) ?? []).map((e) => e.toString()).toList(),
        error = _s(j['error']);

  final List<String> invoiceNos;
  final int convertedOrders;
  final List<String> warnings;
  final String? error;
}

class DraftCustomerGroup {
  DraftCustomerGroup.fromJson(Map<String, dynamic> j)
      : customerName = j['customerName'] ?? '',
        customerPhone = j['customerPhone'] ?? '',
        orderIds = ((j['orderIds'] as List?) ?? []).map((e) => e.toString()).toList(),
        taxPercents = ((j['taxPercents'] as List?) ?? []).map((e) => _d(e)).toList(),
        suggestedInvoiceNo = j['suggestedInvoiceNo'] ?? '';

  final String customerName;
  final String customerPhone;
  final List<String> orderIds;
  final List<double> taxPercents;
  final String suggestedInvoiceNo;
}

class DraftFile {
  DraftFile.fromJson(Map<String, dynamic> j)
      : invoiceNo = j['invoiceNo'] ?? '',
        taxPercent = _d(j['taxPercent']),
        fileId = _s(j['fileId']),
        fileName = _s(j['fileName']);

  final String invoiceNo;
  final double taxPercent;
  final String? fileId;
  final String? fileName;
}

class DraftGroupResult {
  DraftGroupResult.fromJson(Map<String, dynamic> j)
      : invoiceNo = j['invoiceNo'] ?? '',
        success = j['success'] ?? false,
        error = _s(j['error']),
        files = ((j['files'] as List?) ?? []).map((e) => DraftFile.fromJson(e)).toList();

  final String invoiceNo;
  final bool success;
  final String? error;
  final List<DraftFile> files;
}
