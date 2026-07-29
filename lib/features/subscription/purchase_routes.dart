import 'package:flutter/material.dart';

import '../photosession/theme/photosession_theme_scope.dart';
import 'paywall_screen.dart';
import 'token_purchase_screen.dart';

Route<T> paywallRoute<T>({VoidCallback? onClose}) {
  return photosessionRoute<T>(PaywallScreen(onClose: onClose));
}

Route<T> tokenPurchaseRoute<T>() {
  return photosessionRoute<T>(const TokenPurchaseScreen());
}
