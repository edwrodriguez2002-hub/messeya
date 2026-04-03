import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/config/backend_config.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../shared/models/company.dart';

final companyBillingServiceProvider = Provider<CompanyBillingService>((ref) {
  final service = CompanyBillingService(ref.watch(firebaseAuthProvider));
  ref.onDispose(service.dispose);
  return service;
});

final companySubscriptionProductProvider =
    FutureProvider<CompanySubscriptionProduct?>((ref) {
  return ref.watch(companyBillingServiceProvider).loadSubscriptionProduct();
});

final companyBillingAvailabilityProvider =
    FutureProvider<CompanyBillingAvailability>((ref) {
  return ref.watch(companyBillingServiceProvider).loadAvailability();
});

class CompanySubscriptionProduct {
  const CompanySubscriptionProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.priceLabel,
  });

  final String id;
  final String title;
  final String description;
  final String priceLabel;
}

class CompanyBillingAvailability {
  const CompanyBillingAvailability({
    required this.isReady,
    required this.message,
    this.product,
  });

  final bool isReady;
  final String message;
  final CompanySubscriptionProduct? product;
}

class CompanyBillingResult {
  const CompanyBillingResult({
    required this.planStatus,
    required this.planName,
    required this.message,
    required this.renewsAt,
  });

  final String planStatus;
  final String planName;
  final String message;
  final DateTime? renewsAt;
}

class CompanyBillingService {
  CompanyBillingService(this._auth)
      : _purchaseSubscription =
            InAppPurchase.instance.purchaseStream.listen(null) {
    _purchaseSubscription
      ..onData(_handlePurchaseUpdates)
      ..onError(_handlePurchaseError);
  }

  final FirebaseAuth _auth;
  final StreamSubscription<List<PurchaseDetails>> _purchaseSubscription;
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;

  _PendingBillingOperation? _pendingOperation;

  Future<CompanyBillingAvailability> loadAvailability() async {
    if (!_supportsPlayBilling()) {
      return const CompanyBillingAvailability(
        isReady: false,
        message: 'Disponible solo en Android real con Google Play habilitado.',
      );
    }

    try {
      final available = await _inAppPurchase.isAvailable();
      if (!available) {
        return const CompanyBillingAvailability(
          isReady: false,
          message:
              'Google Play Billing no esta disponible en este dispositivo.',
        );
      }

      final product = await loadSubscriptionProduct();
      if (product == null) {
        return const CompanyBillingAvailability(
          isReady: false,
          message: 'El plan empresarial todavia no esta listo en Play Console.',
        );
      }

      return CompanyBillingAvailability(
        isReady: true,
        message: 'Plan empresarial disponible para activar.',
        product: product,
      );
    } catch (_) {
      return const CompanyBillingAvailability(
        isReady: false,
        message:
            'No pudimos conectar con Google Play desde este equipo. Pruebalo en un Android fisico con Play Store.',
      );
    }
  }

  Future<CompanySubscriptionProduct?> loadSubscriptionProduct() async {
    if (!_supportsPlayBilling()) return null;

    final response = await _inAppPurchase.queryProductDetails({
      BackendConfig.companySubscriptionProductId,
    });

    if (response.error != null) {
      throw Exception(response.error!.message);
    }

    if (response.productDetails.isEmpty) {
      return null;
    }

    final product = response.productDetails.first;
    return CompanySubscriptionProduct(
      id: product.id,
      title: product.title,
      description: product.description,
      priceLabel: product.price,
    );
  }

  Future<CompanyBillingResult> purchaseCompanyPlan({
    Company? company,
  }) async {
    if (!_supportsPlayBilling()) {
      throw Exception(
          'La compra por Play Store solo esta disponible en Android.');
    }

    if (!await _inAppPurchase.isAvailable()) {
      throw Exception(
          'Google Play Billing no esta disponible en este dispositivo.');
    }

    final response = await _inAppPurchase.queryProductDetails({
      BackendConfig.companySubscriptionProductId,
    });

    if (response.error != null) {
      throw Exception(response.error!.message);
    }

    if (response.productDetails.isEmpty) {
      throw Exception(
        'No encontramos el producto empresarial en Play Console. Revisa el product ID.',
      );
    }

    final product = response.productDetails.first;
    final completer = Completer<CompanyBillingResult>();
    _replacePendingOperation(
      _PendingBillingOperation(
        companyId: company?.id,
        completer: completer,
      ),
    );

    final started = await _inAppPurchase.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );

    if (!started) {
      _completePendingWithError('No pudimos iniciar la compra en Google Play.');
    }

    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        _completePendingWithError(
          'La compra tardo demasiado en responder. Intenta de nuevo.',
        );
        throw Exception(
          'La compra tardo demasiado en responder. Intenta de nuevo.',
        );
      },
    );
  }

  Future<CompanyBillingResult> restoreCompanyPlan({
    Company? company,
  }) async {
    if (!_supportsPlayBilling()) {
      throw Exception(
        'La restauracion por Play Store solo esta disponible en Android.',
      );
    }

    if (!await _inAppPurchase.isAvailable()) {
      throw Exception(
          'Google Play Billing no esta disponible en este dispositivo.');
    }

    final completer = Completer<CompanyBillingResult>();
    _replacePendingOperation(
      _PendingBillingOperation(
        companyId: company?.id,
        completer: completer,
      ),
    );

    await _inAppPurchase.restorePurchases();
    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        _completePendingWithError(
          'No recibimos una compra restaurable de Google Play.',
        );
        throw Exception(
          'No recibimos una compra restaurable de Google Play.',
        );
      },
    );
  }

  Future<CompanyBillingResult> refreshCompanyPlan({
    Company? company,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No hay una sesion activa.');
    }

    final idToken = await user.getIdToken(true);
    final response = await http.post(
      BackendConfig.buildUri('/api/refresh-company-subscription'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        if (company != null) 'companyId': company.id,
      }),
    );

    final payload = _decodePayload(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        payload['error']?.toString() ??
            'No pudimos actualizar el plan empresarial.',
      );
    }

    return _mapBillingResult(payload);
  }

  Future<void> openSubscriptionManagement() async {
    final url = Uri.parse(
      'https://play.google.com/store/account/subscriptions?package=${BackendConfig.androidPackageName}&sku=${BackendConfig.companySubscriptionProductId}',
    );
    if (!await launchUrlString(url.toString())) {
      throw Exception('No pudimos abrir la gestion de suscripciones.');
    }
  }

  void dispose() {
    _purchaseSubscription.cancel();
  }

  bool _supportsPlayBilling() {
    return !kIsWeb && Platform.isAndroid;
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    final pending = _pendingOperation;
    if (pending == null) return;

    for (final purchase in purchaseDetailsList) {
      if (purchase.productID != BackendConfig.companySubscriptionProductId) {
        continue;
      }

      if (purchase.status == PurchaseStatus.pending) {
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        _completePendingWithError(
          purchase.error?.message ?? 'La compra fue rechazada por Google Play.',
        );
        await _finishPurchaseIfNeeded(purchase);
        return;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        _completePendingWithError('La compra fue cancelada.');
        await _finishPurchaseIfNeeded(purchase);
        return;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          final result = await _verifyPurchaseForCompany(
            companyId: pending.companyId,
            purchase: purchase,
          );
          pending.complete(result);
        } catch (error) {
          pending.completeError(error);
        } finally {
          await _finishPurchaseIfNeeded(purchase);
          _pendingOperation = null;
        }
        return;
      }
    }
  }

  void _handlePurchaseError(Object error) {
    _completePendingWithError(error.toString());
  }

  Future<CompanyBillingResult> _verifyPurchaseForCompany({
    String? companyId,
    required PurchaseDetails purchase,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No hay una sesion activa.');
    }

    final purchaseToken = purchase.verificationData.serverVerificationData;
    if (purchaseToken.trim().isEmpty) {
      throw Exception('Google Play no devolvio un purchaseToken valido.');
    }

    final idToken = await user.getIdToken(true);
    final response = await http.post(
      BackendConfig.buildUri('/api/verify-company-subscription'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        if (companyId != null && companyId.isNotEmpty) 'companyId': companyId,
        'purchaseToken': purchaseToken,
        'productId': purchase.productID,
      }),
    );

    final payload = _decodePayload(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        payload['error']?.toString() ??
            'No pudimos validar la suscripcion con Google Play.',
      );
    }

    return _mapBillingResult(payload);
  }

  Future<void> _finishPurchaseIfNeeded(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    await _inAppPurchase.completePurchase(purchase);
  }

  void _replacePendingOperation(_PendingBillingOperation operation) {
    _pendingOperation?.completeError(
      Exception('Cancelamos la operacion anterior para iniciar una nueva.'),
    );
    _pendingOperation = operation;
  }

  void _completePendingWithError(String message) {
    final pending = _pendingOperation;
    if (pending == null) return;
    pending.completeError(Exception(message));
    _pendingOperation = null;
  }

  Map<String, dynamic> _decodePayload(http.Response response) {
    if (response.body.isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return const {};
  }

  CompanyBillingResult _mapBillingResult(Map<String, dynamic> payload) {
    return CompanyBillingResult(
      planStatus: payload['planStatus']?.toString() ?? 'inactive',
      planName: payload['planName']?.toString() ?? 'business',
      message: payload['message']?.toString() ?? 'Plan actualizado.',
      renewsAt: _tryParseDate(payload['renewsAt']?.toString()),
    );
  }

  DateTime? _tryParseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}

class _PendingBillingOperation {
  const _PendingBillingOperation({
    required this.companyId,
    required this.completer,
  });

  final String? companyId;
  final Completer<CompanyBillingResult> completer;

  void complete(CompanyBillingResult result) {
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  void completeError(Object error) {
    if (!completer.isCompleted) {
      completer.completeError(error);
    }
  }
}
