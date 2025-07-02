/// 플랜 정보를 나타내는 모델 클래스
class Plan {
  final String type;
  final String name;
  final bool isFreeTrial;
  final int daysRemaining;
  final DateTime? expiryDate;
  final String? status;
  final bool hasUsedFreeTrial;
  final Map<String, int> limits;

  const Plan({
    required this.type,
    required this.name,
    this.isFreeTrial = false,
    this.daysRemaining = 0,
    this.expiryDate,
    this.status,
    this.hasUsedFreeTrial = false,
    required this.limits,
  });

  /// 무료 플랜 생성
  factory Plan.free({Map<String, int>? limits}) {
    return Plan(
      type: 'free',
      name: '무료',
      limits: limits ?? {
        'ocrPages': 30,
        'translatedChars': 10000,
        'ttsRequests': 0,
        'storageBytes': 52428800,
      },
    );
  }

  /// 프리미엄 플랜 생성
  factory Plan.premium({Map<String, int>? limits}) {
    return Plan(
      type: 'premium',
      name: '프리미엄',
      limits: limits ?? {
        'ocrPages': 300,
        'translatedChars': 100000,
        'ttsRequests': 1000,
        'storageBytes': 1073741824,
      },
    );
  }

  /// 프리미엄 체험 플랜 생성
  factory Plan.premiumTrial({
    required int daysRemaining,
    DateTime? expiryDate,
    Map<String, int>? limits,
  }) {
    return Plan(
      type: 'premium',
      name: '프리미엄 체험 (${daysRemaining}일 남음)',
      isFreeTrial: true,
      daysRemaining: daysRemaining,
      expiryDate: expiryDate,
      status: 'trial',
      limits: limits ?? {
        'ocrPages': 300,
        'translatedChars': 100000,
        'ttsRequests': 1000,
        'storageBytes': 1073741824,
      },
    );
  }

  /// JSON에서 Plan 객체 생성
  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      type: json['type'] as String,
      name: json['name'] as String,
      isFreeTrial: json['isFreeTrial'] as bool? ?? false,
      daysRemaining: json['daysRemaining'] as int? ?? 0,
      expiryDate: json['expiryDate'] != null 
          ? DateTime.parse(json['expiryDate'] as String)
          : null,
      status: json['status'] as String?,
      hasUsedFreeTrial: json['hasUsedFreeTrial'] as bool? ?? false,
      limits: Map<String, int>.from(json['limits'] as Map? ?? {}),
    );
  }

  /// Plan 객체를 JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'name': name,
      'isFreeTrial': isFreeTrial,
      'daysRemaining': daysRemaining,
      'expiryDate': expiryDate?.toIso8601String(),
      'status': status,
      'hasUsedFreeTrial': hasUsedFreeTrial,
      'limits': limits,
    };
  }

  /// 플랜이 활성 상태인지 확인
  bool get isActive {
    if (expiryDate == null) return type == 'free';
    return expiryDate!.isAfter(DateTime.now());
  }

  /// 플랜 복사 (일부 속성 변경)
  Plan copyWith({
    String? type,
    String? name,
    bool? isFreeTrial,
    int? daysRemaining,
    DateTime? expiryDate,
    String? status,
    bool? hasUsedFreeTrial,
    Map<String, int>? limits,
  }) {
    return Plan(
      type: type ?? this.type,
      name: name ?? this.name,
      isFreeTrial: isFreeTrial ?? this.isFreeTrial,
      daysRemaining: daysRemaining ?? this.daysRemaining,
      expiryDate: expiryDate ?? this.expiryDate,
      status: status ?? this.status,
      hasUsedFreeTrial: hasUsedFreeTrial ?? this.hasUsedFreeTrial,
      limits: limits ?? this.limits,
    );
  }

  @override
  String toString() {
    return 'Plan(type: $type, name: $name, isFreeTrial: $isFreeTrial, daysRemaining: $daysRemaining)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Plan &&
        other.type == type &&
        other.name == name &&
        other.isFreeTrial == isFreeTrial &&
        other.daysRemaining == daysRemaining;
  }

  @override
  int get hashCode {
    return type.hashCode ^
        name.hashCode ^
        isFreeTrial.hashCode ^
        daysRemaining.hashCode;
  }
} 