import 'package:equatable/equatable.dart';
import '../constants/subscription_constants.dart';

/// 구독 플랜을 나타내는 모델 클래스
class Plan extends Equatable {
  final String id;
  final String name;
  final bool isPremium;

  const Plan({
    required this.id,
    required this.name,
    required this.isPremium,
  });

  /// 무료 플랜
  factory Plan.free() => const Plan(
    id: 'free',
    name: '무료',
    isPremium: false,
  );

  /// 프리미엄 월간 플랜
  factory Plan.premiumMonthly() => const Plan(
    id: 'premium_monthly',
    name: '프리미엄 (월간)',
    isPremium: true,
  );

  /// 프리미엄 연간 플랜
  factory Plan.premiumYearly() => const Plan(
    id: 'premium_yearly',
    name: '프리미엄 (연간)',
    isPremium: true,
  );

  /// ID로부터 플랜 생성 (중앙화된 상수 사용)
  factory Plan.fromId(String id) {
    switch (id) {
      case 'premium_monthly':
        return Plan.premiumMonthly();
      case 'premium_yearly':
        return Plan.premiumYearly();
      case 'free':
      default:
        return Plan.free();
    }
  }

  /// 🎯 중앙화된 상수에서 플랜 표시 이름 가져오기
  String get displayName => SubscriptionConstants.getPlanDisplayName(id);

  @override
  List<Object?> get props => [id, name, isPremium];

  @override
  String toString() => 'Plan(id: $id, name: $name, isPremium: $isPremium)';
} 