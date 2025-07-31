import '../utils/string_utils.dart';

/// 프리미엄 업그레이드 요청 폼 데이터 모델
class UpgradeRequestForm {
  /// 추가로 필요한 기능들 (체크박스)
  final bool needAdditionalNoteFeature;
  final bool needListeningFeature;
  final bool needOtherFeatures;
  
  /// 기타 기능 요청 (자유 입력)
  final String? otherFeatureRequest;
  
  /// 피카북에 이런 기능이 있었으면 좋겠어요 (자유 입력)
  final String? featureSuggestion;
  
  /// 인터뷰 참여 의향
  final bool? interviewParticipation;
  
  /// 연락처 (인터뷰 참여 시에만)
  final String? contactInfo;
  
  /// 사용자 이메일
  final String? userEmail;
  
  /// 사용자 이름
  final String? userName;

  UpgradeRequestForm({
    this.needAdditionalNoteFeature = false,
    this.needListeningFeature = false,
    this.needOtherFeatures = false,
    this.otherFeatureRequest,
    this.featureSuggestion,
    this.interviewParticipation,
    this.contactInfo,
    this.userEmail,
    this.userName,
  });

  /// 이메일 본문 생성
  String generateEmailBody() {
    final buffer = StringBuffer();
    
    buffer.writeln('=== 사용량 추가 요청 ===');
    buffer.writeln('');
    
    // 사용자 정보
    if (StringUtils.isNotNullOrEmpty(userName)) {
      buffer.writeln('사용자 이름: $userName');
    }
    if (StringUtils.isNotNullOrEmpty(userEmail)) {
      buffer.writeln('사용자 이메일: $userEmail');
    }
    buffer.writeln('');
    
    // 추가로 필요한 기능
    buffer.writeln('📋 추가로 필요한 기능:');
    if (needAdditionalNoteFeature) {
      buffer.writeln('✅ 추가 노트 생성기능');
    }
    if (needListeningFeature) {
      buffer.writeln('✅ 듣기 기능');
    }
    if (needOtherFeatures) {
      buffer.writeln('✅ 기타');
    }
    if (!needAdditionalNoteFeature && !needListeningFeature && !needOtherFeatures) {
      buffer.writeln('❌ 선택된 기능 없음');
    }
    buffer.writeln('');
    
    // 기타 기능 요청
    if (StringUtils.isNotNullOrEmpty(otherFeatureRequest)) {
      buffer.writeln('💡 기타 기능 요청:');
      buffer.writeln(otherFeatureRequest);
      buffer.writeln('');
    }
    
    // 기능 제안
    if (StringUtils.isNotNullOrEmpty(featureSuggestion)) {
      buffer.writeln('💭 피카북에 이런 기능이 있었으면 좋겠어요:');
      buffer.writeln(featureSuggestion);
      buffer.writeln('');
    }
    
    // 인터뷰 참여 의향
    buffer.writeln('🎤 사용자 경험 개선을 위한 인터뷰 참여 의향:');
    if (interviewParticipation == true) {
      buffer.writeln('✅ 예');
      if (StringUtils.isNotNullOrEmpty(contactInfo)) {
        buffer.writeln('📞 연락처: $contactInfo');
      }
    } else if (interviewParticipation == false) {
      buffer.writeln('❌ 아니오');
    } else {
      buffer.writeln('❓ 선택하지 않음');
    }
    buffer.writeln('');
    
    buffer.writeln('=== 요청 완료 ===');
    
    return buffer.toString();
  }

  /// 이메일 제목 생성
  String generateEmailSubject() {
    return '[피카북] 사용량 추가 요청';
  }

  /// 폼 유효성 검사
  bool isValid() {
    // 최소한 하나의 기능이 선택되었거나 기능 제안이 있어야 함
    final hasFeatureRequest = needAdditionalNoteFeature || 
                             needListeningFeature || 
                             needOtherFeatures ||
                             StringUtils.isNotNullOrEmpty(featureSuggestion);
    
    // 인터뷰 참여를 선택했다면 연락처가 필요
    final hasValidContact = interviewParticipation != true || 
                           StringUtils.isNotNullOrEmpty(contactInfo);
    
    return hasFeatureRequest && hasValidContact;
  }

  /// 복사본 생성
  UpgradeRequestForm copyWith({
    bool? needAdditionalNoteFeature,
    bool? needListeningFeature,
    bool? needOtherFeatures,
    String? otherFeatureRequest,
    String? featureSuggestion,
    bool? interviewParticipation,
    String? contactInfo,
    String? userEmail,
    String? userName,
  }) {
    return UpgradeRequestForm(
      needAdditionalNoteFeature: needAdditionalNoteFeature ?? this.needAdditionalNoteFeature,
      needListeningFeature: needListeningFeature ?? this.needListeningFeature,
      needOtherFeatures: needOtherFeatures ?? this.needOtherFeatures,
      otherFeatureRequest: otherFeatureRequest ?? this.otherFeatureRequest,
      featureSuggestion: featureSuggestion ?? this.featureSuggestion,
      interviewParticipation: interviewParticipation ?? this.interviewParticipation,
      contactInfo: contactInfo ?? this.contactInfo,
      userEmail: userEmail ?? this.userEmail,
      userName: userName ?? this.userName,
    );
  }
} 