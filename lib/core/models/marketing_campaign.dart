import 'package:flutter/material.dart';

/// 마케팅 캠페인 데이터 모델
/// 
/// 사용자 환영 메시지, 프로모션, 신규 기능 안내 등 다양한 마케팅 캠페인을
/// 표현하기 위한 데이터 구조입니다.
class MarketingCampaign {
  /// 캠페인 고유 식별자
  final String id;
  
  /// 캠페인 제목
  final String title;
  
  /// 캠페인 상세 설명
  final String description;
  
  /// 캠페인 이미지 경로
  final String imagePath;
  
  /// 캠페인 시작 날짜
  final DateTime startDate;
  
  /// 캠페인 종료 날짜 (null이면 무기한)
  final DateTime? endDate;
  
  /// 캠페인이 표시될 화면 (예: 'home', 'detail', 'all')
  final String targetScreen;
  
  /// SharedPreferences에 저장될 키 (사용자가 이미 본 캠페인인지 확인용)
  final String prefsKey;
  
  /// 캠페인 스타일
  final CampaignStyle style;
  
  /// 사용자가 캠페인을 확인하고 닫을 때 실행할 액션 (옵션)
  final VoidCallback? onAction;
  
  /// 취소 버튼에 표시될 텍스트 (기본값: '닫기')
  final String dismissButtonText;
  
  /// 확인 버튼에 표시될 텍스트 (옵션)
  final String? actionButtonText;
  
  const MarketingCampaign({
    required this.id,
    required this.title,
    required this.description,
    required this.imagePath,
    required this.startDate,
    this.endDate,
    required this.targetScreen,
    required this.prefsKey,
    this.style = CampaignStyle.primary,
    this.onAction,
    this.dismissButtonText = '닫기',
    this.actionButtonText,
  });
  
  /// 현재 캠페인이 활성화 상태인지 확인
  bool isActive() {
    final now = DateTime.now();
    return now.isAfter(startDate) && 
           (endDate == null || now.isBefore(endDate!));
  }
  
  /// 현재 캠페인이 특정 화면에 표시되어야 하는지 확인
  bool shouldShowOnScreen(String screenName) {
    return isActive() && 
           (targetScreen == screenName || targetScreen == 'all');
  }
  
  /// 캠페인을 Map 형태로 변환 (JSON 직렬화용)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'imagePath': imagePath,
      'startDate': startDate.millisecondsSinceEpoch,
      'endDate': endDate?.millisecondsSinceEpoch,
      'targetScreen': targetScreen,
      'prefsKey': prefsKey,
      'style': style.index,
      'dismissButtonText': dismissButtonText,
      'actionButtonText': actionButtonText,
    };
  }
  
  /// Map에서 캠페인 객체 생성 (JSON 역직렬화용)
  factory MarketingCampaign.fromMap(Map<String, dynamic> map) {
    return MarketingCampaign(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      imagePath: map['imagePath'],
      startDate: DateTime.fromMillisecondsSinceEpoch(map['startDate']),
      endDate: map['endDate'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['endDate']) 
          : null,
      targetScreen: map['targetScreen'],
      prefsKey: map['prefsKey'],
      style: CampaignStyle.values[map['style'] ?? 0],
      dismissButtonText: map['dismissButtonText'] ?? '닫기',
      actionButtonText: map['actionButtonText'],
    );
  }
}

/// 캠페인 스타일 정의
enum CampaignStyle {
  /// 주요 강조 스타일 (예: 브랜드 주 색상)
  primary,
  
  /// 보조 스타일
  secondary,
  
  /// 중립 스타일 (흰색/회색 배경)
  neutral,
  
  /// 특별 이벤트 스타일 (예: 축하, 기념일)
  special,
  
  /// 알림 스타일 (중요 공지)
  alert
} 