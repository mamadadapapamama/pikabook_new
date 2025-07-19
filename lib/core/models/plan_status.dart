/// Firestore `status` 필드와 매핑되는 구독 상태 열거형
enum PlanStatus {
  active,
  cancelling,
  expired,
  unverified, // ✅ JWS 검증이 아직 안된 상태
  unknown;

  static PlanStatus fromString(String status) {
    switch (status) {
      case 'active':
        return PlanStatus.active;
      case 'cancelling':
        return PlanStatus.cancelling;
      case 'expired':
        return PlanStatus.expired;
      case 'unverified':
        return PlanStatus.unverified;
      default:
        return PlanStatus.unknown;
    }
  }
}