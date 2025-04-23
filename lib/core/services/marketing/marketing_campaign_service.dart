import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/marketing_campaign.dart';

/// 마케팅 캠페인 관리 서비스
/// 
/// 다양한 마케팅 캠페인을 관리하고, 사용자가 이미 본 캠페인인지 추적합니다.
/// 홈 화면, 상세 화면 등 특정 화면에 표시할 적절한 캠페인을 찾아 제공합니다.
class MarketingCampaignService {
  // 싱글톤 패턴 적용
  static final MarketingCampaignService _instance = MarketingCampaignService._internal();
  factory MarketingCampaignService() => _instance;
  MarketingCampaignService._internal();
  
  // 현재 활성화된 캠페인 목록
  List<MarketingCampaign> _campaigns = [];
  
  /// 사전 정의된 캠페인 초기화
  Future<void> initialize() async {
    // 기본 캠페인 데이터 로드
    _loadDefaultCampaigns();
    
    // 여기서 서버에서 캠페인 데이터를 가져오거나 로컬 저장소에서 로드할 수 있음
  }
  
  /// 기본 캠페인 데이터 로드
  void _loadDefaultCampaigns() {
    // 현재 하드코딩된 캠페인 목록이지만, 향후 서버에서 가져올 수 있음
    _campaigns = [
      // FTUE 환영 캠페인
      MarketingCampaign(
        id: 'welcome_2023',
        title: '피카북에 오신 걸 환영해요! 🎉',
        description: '4월 30일까지, 교재 이미지 100장까지 무료로 스마트 학습 노트를 만들어보실 수 있어요.\n사용량은 [설정]에서 언제든 확인하실 수 있어요!',
        imagePath: 'assets/images/home_help.png',
        startDate: DateTime(2023, 1, 1),
        endDate: DateTime(2024, 4, 30),
        targetScreen: 'home',
        prefsKey: 'home_help_shown',
        style: CampaignStyle.primary,
      ),
      
      // 추가 캠페인 (예시)
      MarketingCampaign(
        id: 'summer_promo_2023',
        title: '여름 특별 프로모션! 🌞',
        description: '여름 방학 특별 이벤트! 7월 한 달간 프리미엄 기능을 무료로 체험해보세요.',
        imagePath: 'assets/images/summer_promo.png',
        startDate: DateTime(2023, 7, 1),
        endDate: DateTime(2023, 7, 31),
        targetScreen: 'home',
        prefsKey: 'summer_promo_2023_shown',
        style: CampaignStyle.special,
        actionButtonText: '프리미엄 체험하기',
      ),
    ];
  }
  
  /// 특정 화면에 표시할 캠페인 가져오기
  /// 
  /// [screenName]: 현재 화면 이름 (예: 'home', 'detail')
  /// [context]: 빌드 컨텍스트
  /// 
  /// 반환값: 표시할 캠페인. 없으면 null
  Future<MarketingCampaign?> getCampaignForScreen(String screenName, BuildContext context) async {
    // 활성 캠페인 필터링
    final activeCampaigns = _campaigns
        .where((campaign) => campaign.shouldShowOnScreen(screenName))
        .toList();
    
    if (activeCampaigns.isEmpty) return null;
    
    // SharedPreferences 인스턴스 가져오기
    final prefs = await SharedPreferences.getInstance();
    
    // 사용자가 아직 보지 않은 캠페인 찾기
    for (final campaign in activeCampaigns) {
      final bool alreadySeen = prefs.getBool(campaign.prefsKey) ?? false;
      if (!alreadySeen) {
        return campaign;
      }
    }
    
    // 모든 캠페인을 이미 봤으면 null 반환
    return null;
  }
  
  /// 캠페인을 사용자가 본 것으로 표시
  Future<void> markCampaignAsSeen(MarketingCampaign campaign) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(campaign.prefsKey, true);
  }
  
  /// 캠페인을 본 것을 초기화 (테스트용)
  Future<void> resetCampaignSeen(String campaignId) async {
    final campaign = _campaigns.firstWhere(
      (c) => c.id == campaignId,
      orElse: () => throw Exception('캠페인을 찾을 수 없습니다: $campaignId'),
    );
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(campaign.prefsKey, false);
  }
  
  /// 모든 캠페인을 본 것을 초기화 (테스트용)
  Future<void> resetAllCampaigns() async {
    final prefs = await SharedPreferences.getInstance();
    
    for (final campaign in _campaigns) {
      await prefs.setBool(campaign.prefsKey, false);
    }
  }
  
  /// 새 캠페인 추가
  void addCampaign(MarketingCampaign campaign) {
    // 동일 ID의 캠페인이 있으면 제거
    _campaigns.removeWhere((c) => c.id == campaign.id);
    // 새 캠페인 추가
    _campaigns.add(campaign);
  }
  
  /// 모든 활성 캠페인 가져오기
  List<MarketingCampaign> getAllActiveCampaigns() {
    return _campaigns.where((campaign) => campaign.isActive()).toList();
  }
} 