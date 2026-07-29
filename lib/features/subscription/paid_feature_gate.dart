import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'purchase_routes.dart';
import 'subscription_providers.dart';

const String privatePresetRestrictionMessage =
    'Приватные пресеты доступны только по подписке. '
    'Без подписки пресеты остаются публичными';

const String deleteRestrictionMessage =
    'Удаление доступно только по подписке';

Future<bool> ensurePaidFeatureAccess(
  BuildContext context,
  WidgetRef ref, {
  required String message,
}) async {
  final hasPaid =
      await ref.read(subscriptionServiceProvider).hasPaidSubscription();
  if (hasPaid) return true;
  if (!context.mounted) return false;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
    ),
  );
  if (!context.mounted) return false;
  await Navigator.of(context).push<void>(paywallRoute<void>());
  return false;
}

Future<bool> ensurePrivatePresetAccess(
  BuildContext context,
  WidgetRef ref,
) =>
    ensurePaidFeatureAccess(
      context,
      ref,
      message: privatePresetRestrictionMessage,
    );

Future<bool> ensureDeleteAccess(
  BuildContext context,
  WidgetRef ref,
) =>
    ensurePaidFeatureAccess(
      context,
      ref,
      message: deleteRestrictionMessage,
    );
