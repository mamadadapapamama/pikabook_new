/// 사용자 설정 모델
/// 사용자의 모든 설정을 관리합니다.

class UserPreferences {
  /// 온보딩 완료 여부
  final bool onboardingCompleted;

  /// 기본 노트 스페이스
  final String defaultNoteSpace;

  /// 사용자 이름
  final String? userName;

  /// 학습 목적
  final String? learningPurpose;

  /// 세그먼트 모드 사용 여부
  final bool useSegmentMode;

  /// 노트 스페이스 목록
  final List<String> noteSpaces;

  /// 소스 언어
  final String sourceLanguage;

  /// 타겟 언어
  final String targetLanguage;

  /// 로그인 기록
  final bool hasLoginHistory;

  UserPreferences({
    this.onboardingCompleted = false,
    this.defaultNoteSpace = '기본 노트',
    this.userName,
    this.learningPurpose,
    this.useSegmentMode = false,
    this.noteSpaces = const ['기본 노트'],
    this.sourceLanguage = 'zh-CN',
    this.targetLanguage = 'ko',
    this.hasLoginHistory = false,
  });

  /// JSON에서 생성
  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      defaultNoteSpace: json['defaultNoteSpace'] as String? ?? '기본 노트',
      userName: json['userName'] as String?,
      learningPurpose: json['learningPurpose'] as String?,
      useSegmentMode: json['translationMode'] == 'segment',
      noteSpaces: (json['noteSpaces'] as List<dynamic>?)?.map((e) => e as String).toList() ?? ['기본 노트'],
      sourceLanguage: json['sourceLanguage'] as String? ?? 'zh-CN',
      targetLanguage: json['targetLanguage'] as String? ?? 'ko',
      hasLoginHistory: json['hasLoginHistory'] as bool? ?? false,
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'onboardingCompleted': onboardingCompleted,
      'defaultNoteSpace': defaultNoteSpace,
      'userName': userName,
      'learningPurpose': learningPurpose,
      'translationMode': useSegmentMode ? 'segment' : 'full',
      'noteSpaces': noteSpaces,
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'hasLoginHistory': hasLoginHistory,
    };
  }

  /// 복사본 생성 (일부 필드 업데이트)
  UserPreferences copyWith({
    bool? onboardingCompleted,
    String? defaultNoteSpace,
    String? userName,
    String? learningPurpose,
    bool? useSegmentMode,
    List<String>? noteSpaces,
    String? sourceLanguage,
    String? targetLanguage,
    bool? hasLoginHistory,
  }) {
    return UserPreferences(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      defaultNoteSpace: defaultNoteSpace ?? this.defaultNoteSpace,
      userName: userName ?? this.userName,
      learningPurpose: learningPurpose ?? this.learningPurpose,
      useSegmentMode: useSegmentMode ?? this.useSegmentMode,
      noteSpaces: noteSpaces ?? this.noteSpaces,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      hasLoginHistory: hasLoginHistory ?? this.hasLoginHistory,
    );
  }

  /// 기본 설정으로 초기화
  factory UserPreferences.defaults() {
    return UserPreferences();
  }
} 