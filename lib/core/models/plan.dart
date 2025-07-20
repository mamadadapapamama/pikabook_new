import '../constants/plan_constants.dart';

/// 플랜 정보를 나타내는 모델 클래스
class Plan {
  final String id;
  final String name;
  final Map<String, int> limits;

  const Plan({required this.id, required this.name, required this.limits});

  factory Plan.fromId(String id) {
    switch (id) {
      case 'premium_monthly':
        return Plan.premiumMonthly();
      case 'premium_yearly':
        return Plan.premiumYearly();
      case 'free_monthly':
      default:
        return Plan.free();
    }
  }

  factory Plan.free() {
    return Plan(
      id: 'free_monthly',
      name: '무료 플랜',
      limits: PlanConstants.PLAN_LIMITS[PlanConstants.PLAN_FREE]!,
    );
  }

  factory Plan.premium() {
    return Plan(
      id: 'premium_monthly', // 대표 ID
      name: '프리미엄',
      limits: PlanConstants.PLAN_LIMITS[PlanConstants.PLAN_PREMIUM]!,
    );
  }

  factory Plan.premiumMonthly() {
    return Plan(
      id: 'premium_monthly',
      name: '프리미엄 (월간)',
      limits: PlanConstants.PLAN_LIMITS[PlanConstants.PLAN_PREMIUM]!,
    );
  }

  factory Plan.premiumYearly() {
    return Plan(
      id: 'premium_yearly',
      name: '프리미엄 (연간)',
      limits: PlanConstants.PLAN_LIMITS[PlanConstants.PLAN_PREMIUM]!,
    );
  }

  bool get isPremium => id.startsWith('premium');
} 