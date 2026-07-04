/// Store product ids.
///
/// A single non-consumable "Pro" unlock (removes ads + trackpad mouse + the
/// future More button). You must create a product with **exactly this id** in
/// both Google Play Console and App Store Connect, and set its price there.
class PurchaseIds {
  const PurchaseIds._();

  /// The one and only product: the lifetime Pro unlock.
  static const String pro = 'pro_unlock';

  /// All ids to query from the store.
  static const Set<String> all = {pro};
}

/// The shared_preferences key that persists the Pro entitlement locally.
const String kProEntitlementKey = 'pro_unlocked';
