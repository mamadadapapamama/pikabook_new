import 'package:flutter/material.dart';
import '../models/marketing_campaign.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../services/marketing/marketing_campaign_service.dart';

/// 마케팅 캠페인을 표시하는 위젯
/// 
/// 홈 화면, 상세 화면 등 다양한 화면에서 마케팅 캠페인을 통일된 방식으로 표시하기 위한 위젯입니다.
/// HelpTextTooltip을 기반으로 확장하여 마케팅 캠페인 데이터 모델을 사용할 수 있도록 합니다.
class MarketingCampaignWidget extends StatelessWidget {
  /// 표시할 마케팅 캠페인 데이터
  final MarketingCampaign campaign;
  
  /// 캠페인 닫기 버튼 클릭 시 호출될 콜백
  final VoidCallback onDismiss;
  
  /// 액션 버튼 클릭 시 호출될 콜백 (있는 경우)
  final VoidCallback? onAction;
  
  /// 위젯 너비 (기본값: 화면 너비의 90%)
  final double? width;
  
  /// 내부 요소 간 간격
  final double spacing;
  
  /// 마케팅 서비스 인스턴스
  final MarketingCampaignService _marketingService = MarketingCampaignService();
  
  MarketingCampaignWidget({
    Key? key,
    required this.campaign,
    required this.onDismiss,
    this.onAction,
    this.width,
    this.spacing = 12.0,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // 스타일에 따른 색상 결정
    final Color backgroundColor;
    final Color titleColor;
    final Color borderColor;
    
    switch (campaign.style) {
      case CampaignStyle.primary:
        backgroundColor = ColorTokens.primarylight;
        titleColor = ColorTokens.primary;
        borderColor = ColorTokens.primarylight;
        break;
      case CampaignStyle.secondary:
        backgroundColor = ColorTokens.secondaryLight;
        titleColor = ColorTokens.secondary;
        borderColor = ColorTokens.secondaryLight;
        break;
      case CampaignStyle.neutral:
        backgroundColor = ColorTokens.surface;
        titleColor = ColorTokens.textPrimary;
        borderColor = ColorTokens.greyLight;
        break;
      case CampaignStyle.special:
        backgroundColor = ColorTokens.primaryverylight;
        titleColor = ColorTokens.primary;
        borderColor = ColorTokens.secondary;
        break;
      case CampaignStyle.alert:
        backgroundColor = ColorTokens.errorLight;
        titleColor = ColorTokens.error;
        borderColor = ColorTokens.errorLight;
        break;
    }
    
    return Container(
      width: width ?? MediaQuery.of(context).size.width - 32,
      padding: EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 제목 영역
          Text(
            campaign.title,
            style: TypographyTokens.subtitle1.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: titleColor,
            ),
          ),
          
          SizedBox(height: spacing),
          
          // 설명 영역
          Text(
            campaign.description,
            style: const TextStyle(
              fontSize: 14,
              color: ColorTokens.textPrimary,
            ),
          ),
          
          // 이미지가 있는 경우 표시
          if (campaign.imagePath.isNotEmpty) ...[
            SizedBox(height: spacing),
            
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                campaign.imagePath,
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            ),
          ],
          
          SizedBox(height: spacing),
          
          // 버튼 영역
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 닫기 버튼
              TextButton(
                onPressed: () {
                  // 캠페인을 본 것으로 표시
                  _marketingService.markCampaignAsSeen(campaign);
                  onDismiss();
                },
                style: TextButton.styleFrom(
                  foregroundColor: ColorTokens.textSecondary,
                ),
                child: Text(campaign.dismissButtonText),
              ),
              
              // 추가 액션 버튼 (있는 경우)
              if (campaign.actionButtonText != null) ...[
                const SizedBox(width: 8),
                
                ElevatedButton(
                  onPressed: () {
                    // 캠페인을 본 것으로 표시
                    _marketingService.markCampaignAsSeen(campaign);
                    
                    // 캠페인 액션 실행 (있는 경우)
                    if (campaign.onAction != null) {
                      campaign.onAction!();
                    }
                    
                    // 외부에서 제공된 액션 실행 (있는 경우)
                    if (onAction != null) {
                      onAction!();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: titleColor,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(campaign.actionButtonText!),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// FTUE(First Time User Experience) 위젯
/// 
/// 마케팅 캠페인 위젯을 활용해 첫 사용자 경험을 위한 전문 위젯입니다.
class FTUEWidget extends StatelessWidget {
  /// 표시할 화면 이름
  final String screenName;
  
  /// 캠페인 닫기 버튼 클릭 시 호출될 콜백
  final VoidCallback? onDismiss;
  
  /// 액션 버튼 클릭 시 호출될 콜백
  final VoidCallback? onAction;
  
  /// 위젯 너비
  final double? width;
  
  /// 위젯 위치
  final EdgeInsets? position;
  
  /// 마케팅 서비스 인스턴스
  final MarketingCampaignService _marketingService = MarketingCampaignService();
  
  FTUEWidget({
    Key? key,
    required this.screenName,
    this.onDismiss,
    this.onAction,
    this.width,
    this.position,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MarketingCampaign?>(
      future: _marketingService.getCampaignForScreen(screenName, context),
      builder: (context, snapshot) {
        // 데이터 로딩 중이면 빈 위젯 표시
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        
        // 표시할 캠페인이 없으면 빈 위젯 표시
        final campaign = snapshot.data;
        if (campaign == null) {
          return const SizedBox.shrink();
        }
        
        // 위치 지정이 있는 경우 Positioned 위젯으로 감싸기
        if (position != null) {
          return Positioned(
            top: position?.top,
            bottom: position?.bottom,
            left: position?.left,
            right: position?.right,
            child: MarketingCampaignWidget(
              campaign: campaign,
              onDismiss: onDismiss ?? () {},
              onAction: onAction,
              width: width,
            ),
          );
        }
        
        // 위치 지정이 없는 경우 그냥 반환
        return MarketingCampaignWidget(
          campaign: campaign,
          onDismiss: onDismiss ?? () {},
          onAction: onAction,
          width: width,
        );
      },
    );
  }
} 