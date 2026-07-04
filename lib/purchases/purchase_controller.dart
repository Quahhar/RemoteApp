import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_providers.dart';
import 'purchase_ids.dart';

/// Snapshot of the store/entitlement state the UI watches.
class PurchaseState {
  const PurchaseState({
    this.pro = false,
    this.products = const [],
    this.pending = false,
    this.available = false,
    this.error,
  });

  /// The user owns Pro (removes ads + unlocks gated features).
  final bool pro;

  /// Loaded store products (empty until queried / when the store is offline).
  final List<ProductDetails> products;

  /// A purchase or restore is in flight.
  final bool pending;

  /// Whether the store is reachable on this device.
  final bool available;

  /// Last user-facing error, or null.
  final String? error;

  ProductDetails? get proProduct {
    for (final p in products) {
      if (p.id == PurchaseIds.pro) return p;
    }
    return null;
  }

  /// Localized price (e.g. "$2.99"), or null if products haven't loaded.
  String? get proPrice => proProduct?.price;

  PurchaseState copyWith({
    bool? pro,
    List<ProductDetails>? products,
    bool? pending,
    bool? available,
    String? error,
    bool clearError = false,
  }) {
    return PurchaseState(
      pro: pro ?? this.pro,
      products: products ?? this.products,
      pending: pending ?? this.pending,
      available: available ?? this.available,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final purchaseProvider =
    NotifierProvider<PurchaseController, PurchaseState>(PurchaseController.new);

/// Whether Pro is owned — the single gate for ad-removal and paid features.
/// (Override this in widget tests to avoid touching the store.)
final isProProvider = Provider<bool>((ref) => ref.watch(purchaseProvider).pro);

class PurchaseController extends Notifier<PurchaseState> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Timer? _pendingTimeout;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  PurchaseState build() {
    final pro = _prefs.getBool(kProEntitlementKey) ?? false;
    try {
      _sub = _iap.purchaseStream.listen(_onPurchaseUpdates, onError: (_) {});
    } catch (_) {
      // Store unavailable (e.g. in tests) — entitlement still works from prefs.
    }
    ref.onDispose(() {
      _sub?.cancel();
      _pendingTimeout?.cancel();
    });
    _init();
    return PurchaseState(pro: pro);
  }

  Future<void> _init() async {
    try {
      if (!await _iap.isAvailable()) return;
      final resp = await _iap.queryProductDetails(PurchaseIds.all);
      state = state.copyWith(available: true, products: resp.productDetails);
    } catch (_) {
      // Leave defaults; the upgrade screen shows an "unavailable" state.
    }
  }

  /// Start the Pro purchase. Results arrive asynchronously via the stream.
  Future<void> buyPro() async {
    final product = state.proProduct;
    if (product == null) {
      state = state.copyWith(error: 'Upgrade isn’t available right now.');
      return;
    }
    state = state.copyWith(pending: true, clearError: true);
    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (_) {
      state = state.copyWith(pending: false, error: 'Couldn’t start the purchase.');
    }
  }

  /// Restore a previous Pro purchase (required by the App Store).
  Future<void> restore() async {
    state = state.copyWith(pending: true, clearError: true);
    try {
      await _iap.restorePurchases();
    } catch (_) {
      state = state.copyWith(pending: false, error: 'Couldn’t restore purchases.');
      return;
    }
    // Restored items (if any) arrive via the stream; clear the spinner if the
    // store stays silent (e.g. nothing to restore).
    _pendingTimeout?.cancel();
    _pendingTimeout = Timer(const Duration(seconds: 4), () {
      if (state.pending) state = state.copyWith(pending: false);
    });
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(pending: true);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (p.productID == PurchaseIds.pro) await _grantPro();
          state = state.copyWith(pending: false, clearError: true);
        case PurchaseStatus.error:
          state = state.copyWith(
            pending: false,
            error: p.error?.message ?? 'The purchase didn’t go through.',
          );
        case PurchaseStatus.canceled:
          state = state.copyWith(pending: false);
      }
      // Always acknowledge, or the store will replay it forever.
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  Future<void> _grantPro() async {
    await _prefs.setBool(kProEntitlementKey, true);
    state = state.copyWith(pro: true);
  }
}
