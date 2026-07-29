import 'package:flutter/services.dart';
import 'package:flutter_rustore_review/flutter_rustore_review.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StoreReviewOutcome {
  completed,
  alreadyReviewed,
  throttled,
  unavailable,
  failed,
}

class StoreReviewResult {
  const StoreReviewResult({
    required this.outcome,
    required this.appVersion,
  });

  final StoreReviewOutcome outcome;
  final String appVersion;

  bool get shouldAttemptReward =>
      outcome == StoreReviewOutcome.completed ||
      outcome == StoreReviewOutcome.alreadyReviewed;
}

class PostPhotosessionReviewService {
  PostPhotosessionReviewService._();

  static const String _kGenCount = 'post_session_review_success_gen_count';
  static const String _kPromptShownCount =
      'post_session_review_prompt_shown_count';
  static const String _kNextEligibleAtMs =
      'post_session_review_next_eligible_at_ms';
  static const String _kReviewCompleted = 'post_session_review_completed';
  static const String _kReviewRequestedVersion = 'review_requested_version';

  static const int _kMinGenerationsBeforePrompt = 3;
  static const int _kMaxPromptShows = 3;
  static const Duration _kMinInstallAge = Duration(days: 1);
  static const Duration _kCooldownAfterDismiss = Duration(days: 14);
  static const Duration _kCooldownAfterFlowCompleted = Duration(days: 30);
  static const Duration _kCooldownAfterThrottled = Duration(days: 45);
  static const Duration _kLongBlockDuration = Duration(days: 3650);

  static Future<void> recordSuccessfulGeneration(
      SharedPreferences prefs) async {
    final c = (prefs.getInt(_kGenCount) ?? 0) + 1;
    await prefs.setInt(_kGenCount, c);
  }

  static Future<bool> alreadyReviewedThisVersion(
      SharedPreferences prefs) async {
    final info = await PackageInfo.fromPlatform();
    return prefs.getString(_kReviewRequestedVersion) == info.version;
  }

  static Future<bool> shouldShowBanner(SharedPreferences prefs) async {
    if (prefs.getBool(_kReviewCompleted) ?? false) return false;
    if (!_isInstallAgeReached(prefs)) return false;

    final shownCount = prefs.getInt(_kPromptShownCount) ?? 0;
    if (shownCount >= _kMaxPromptShows) return false;

    final genCount = prefs.getInt(_kGenCount) ?? 0;
    if (genCount < _kMinGenerationsBeforePrompt) return false;

    final nextEligibleAt = prefs.getInt(_kNextEligibleAtMs) ?? 0;
    return DateTime.now().millisecondsSinceEpoch >= nextEligibleAt;
  }

  static Future<void> consumeBannerOpportunity(SharedPreferences prefs) async {
    final shown = (prefs.getInt(_kPromptShownCount) ?? 0) + 1;
    await prefs.setInt(_kPromptShownCount, shown);

    if (shown >= _kMaxPromptShows) {
      await _setNextEligibleAfter(prefs, _kLongBlockDuration);
    } else {
      await _setNextEligibleAfter(prefs, _kCooldownAfterDismiss);
    }
  }

  static Future<void> onUserDismissedBanner(SharedPreferences prefs) async {
    await _setNextEligibleAfter(prefs, _kCooldownAfterDismiss);
  }

  static Future<void> markReviewRewardGranted(SharedPreferences prefs) async {
    await prefs.setBool(_kReviewCompleted, true);
    await _setNextEligibleAfter(prefs, _kLongBlockDuration);
  }

  static Future<StoreReviewResult> requestStoreReview(
    SharedPreferences prefs,
  ) async {
    final info = await PackageInfo.fromPlatform();
    final appVersion = info.version;
    const bool isRuStoreBuild = bool.fromEnvironment('RUSTORE');
    if (isRuStoreBuild) {
      if (prefs.getBool(_kReviewCompleted) ?? false) {
        return StoreReviewResult(
          outcome: StoreReviewOutcome.alreadyReviewed,
          appVersion: appVersion,
        );
      }
      try {
        await RustoreReviewClient.request();
        await RustoreReviewClient.review();
        final result = StoreReviewResult(
          outcome: StoreReviewOutcome.completed,
          appVersion: appVersion,
        );
        await _applyOutcomePolicy(prefs, result, isRuStoreBuild: true);
        return result;
      } on PlatformException catch (e) {
        final mapped = _mapRuStoreError(e);
        final result = StoreReviewResult(
          outcome: mapped,
          appVersion: appVersion,
        );
        await _applyOutcomePolicy(prefs, result, isRuStoreBuild: true);
        return result;
      } catch (_) {
        final result = StoreReviewResult(
          outcome: StoreReviewOutcome.failed,
          appVersion: appVersion,
        );
        await _applyOutcomePolicy(prefs, result, isRuStoreBuild: true);
        return result;
      }
    }
    try {
      final lastVersion = prefs.getString(_kReviewRequestedVersion);
      if (lastVersion == appVersion) {
        return StoreReviewResult(
          outcome: StoreReviewOutcome.alreadyReviewed,
          appVersion: appVersion,
        );
      }
      final inAppReview = InAppReview.instance;
      final isAvailable = await inAppReview.isAvailable();
      if (isAvailable) {
        await inAppReview.requestReview();
        await prefs.setString(_kReviewRequestedVersion, appVersion);
        final result = StoreReviewResult(
          outcome: StoreReviewOutcome.completed,
          appVersion: appVersion,
        );
        await _applyOutcomePolicy(prefs, result, isRuStoreBuild: false);
        return result;
      }
      final result = StoreReviewResult(
        outcome: StoreReviewOutcome.unavailable,
        appVersion: appVersion,
      );
      await _applyOutcomePolicy(prefs, result, isRuStoreBuild: false);
      return result;
    } catch (_) {
      final result = StoreReviewResult(
        outcome: StoreReviewOutcome.failed,
        appVersion: appVersion,
      );
      await _applyOutcomePolicy(prefs, result, isRuStoreBuild: false);
      return result;
    }
  }

  static bool _isInstallAgeReached(SharedPreferences prefs) {
    final firstInstallIso = prefs.getString('first_install_date');
    if (firstInstallIso != null && firstInstallIso.isNotEmpty) {
      final dt = DateTime.tryParse(firstInstallIso);
      if (dt != null) {
        return DateTime.now().difference(dt) >= _kMinInstallAge;
      }
    }

    final firstAppLaunchMs = prefs.getInt('first_app_launch');
    if (firstAppLaunchMs != null && firstAppLaunchMs > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(firstAppLaunchMs);
      return DateTime.now().difference(dt) >= _kMinInstallAge;
    }

    return true;
  }

  static Future<void> _setNextEligibleAfter(
    SharedPreferences prefs,
    Duration cooldown,
  ) async {
    final nextAt = DateTime.now().add(cooldown).millisecondsSinceEpoch;
    await prefs.setInt(_kNextEligibleAtMs, nextAt);
  }

  static Future<void> _applyOutcomePolicy(
    SharedPreferences prefs,
    StoreReviewResult result, {
    required bool isRuStoreBuild,
  }) async {
    switch (result.outcome) {
      case StoreReviewOutcome.alreadyReviewed:
        await prefs.setBool(_kReviewCompleted, true);
        await prefs.setString(_kReviewRequestedVersion, result.appVersion);
        await _setNextEligibleAfter(prefs, _kLongBlockDuration);
        return;
      case StoreReviewOutcome.completed:
        if (!isRuStoreBuild) {
          await prefs.setString(_kReviewRequestedVersion, result.appVersion);
        }
        await _setNextEligibleAfter(prefs, _kCooldownAfterFlowCompleted);
        return;
      case StoreReviewOutcome.throttled:
        await _setNextEligibleAfter(prefs, _kCooldownAfterThrottled);
        return;
      case StoreReviewOutcome.unavailable:
      case StoreReviewOutcome.failed:
        await _setNextEligibleAfter(prefs, _kCooldownAfterDismiss);
        return;
    }
  }

  static StoreReviewOutcome _mapRuStoreError(PlatformException error) {
    final payload =
        '${error.code} ${error.message} ${error.details}'.toLowerCase().trim();

    if (payload.contains('rustorereviewexists') ||
        payload.contains('reviewexists')) {
      return StoreReviewOutcome.alreadyReviewed;
    }
    if (payload.contains('requestlimit') || payload.contains('limitreached')) {
      return StoreReviewOutcome.throttled;
    }
    if (payload.contains('notinstalled') ||
        payload.contains('outdated') ||
        payload.contains('unauthorized') ||
        payload.contains('banned') ||
        payload.contains('invalidreviewinfo')) {
      return StoreReviewOutcome.unavailable;
    }

    return StoreReviewOutcome.failed;
  }
}
