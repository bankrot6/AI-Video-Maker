// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'token_usage_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TokenUsageModel _$TokenUsageModelFromJson(Map<String, dynamic> json) =>
    TokenUsageModel(
      totalTokens: (json['totalTokens'] as num).toInt(),
      usedTokens: (json['usedTokens'] as num).toInt(),
      subscriptionTokens: (json['subscriptionTokens'] as num).toInt(),
      purchasedTokens: (json['purchasedTokens'] as num).toInt(),
      lastResetDate: DateTime.parse(json['lastResetDate'] as String),
      lastUsedDate: json['lastUsedDate'] == null
          ? null
          : DateTime.parse(json['lastUsedDate'] as String),
      isTrialUser: json['isTrialUser'] as bool? ?? false,
      trialDaysRemaining: (json['trialDaysRemaining'] as num?)?.toInt(),
      trialStartDate: json['trialStartDate'] == null
          ? null
          : DateTime.parse(json['trialStartDate'] as String),
      trialEndDate: json['trialEndDate'] == null
          ? null
          : DateTime.parse(json['trialEndDate'] as String),
    );

Map<String, dynamic> _$TokenUsageModelToJson(TokenUsageModel instance) =>
    <String, dynamic>{
      'totalTokens': instance.totalTokens,
      'usedTokens': instance.usedTokens,
      'subscriptionTokens': instance.subscriptionTokens,
      'purchasedTokens': instance.purchasedTokens,
      'lastResetDate': instance.lastResetDate.toIso8601String(),
      'lastUsedDate': instance.lastUsedDate?.toIso8601String(),
      'isTrialUser': instance.isTrialUser,
      'trialDaysRemaining': instance.trialDaysRemaining,
      'trialStartDate': instance.trialStartDate?.toIso8601String(),
      'trialEndDate': instance.trialEndDate?.toIso8601String(),
    };

TokenPackageModel _$TokenPackageModelFromJson(Map<String, dynamic> json) =>
    TokenPackageModel(
      type: $enumDecode(_$TokenPackageTypeEnumMap, json['type']),
      title: json['title'] as String,
      description: json['description'] as String,
      tokens: (json['tokens'] as num).toInt(),
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String,
      badge: json['badge'] as String?,
    );

Map<String, dynamic> _$TokenPackageModelToJson(TokenPackageModel instance) =>
    <String, dynamic>{
      'type': _$TokenPackageTypeEnumMap[instance.type]!,
      'title': instance.title,
      'description': instance.description,
      'tokens': instance.tokens,
      'price': instance.price,
      'currency': instance.currency,
      'badge': instance.badge,
    };

const _$TokenPackageTypeEnumMap = {
  TokenPackageType.small: 'small',
  TokenPackageType.medium: 'medium',
  TokenPackageType.large: 'large',
};
