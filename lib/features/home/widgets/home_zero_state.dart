import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/services/common/banner_manager.dart';
import 'banner_builder_helper.dart';

/// 📭 HomeScreen 제로 상태 위젯
/// 
/// 책임:
/// - 노트가 없을 때의 UI 표시
/// - 활성 배너들 표시
/// - 안내 메시지 및 이미지 표시
class HomeZeroState extends StatelessWidget {
  final List<BannerType> activeBanners;
  final Function(BannerType) onShowUpgradeModal;
  final Function(BannerType) onDismissBanner;

  const HomeZeroState({
    super.key,
    required this.activeBanners,
    required this.onShowUpgradeModal,
    required this.onDismissBanner,
  });

  @override
  Widget build(BuildContext context) {
            return Column(
          children: [
            // 🎯 활성 배너들 표시
            ...BannerBuilderHelper.buildActiveBanners(
              activeBanners: activeBanners,
              onShowUpgradeModal: onShowUpgradeModal,
              onDismissBanner: onDismissBanner,
            ),
            
            // 제로 스테이트 콘텐츠
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/zeronote.png',
                      width: 200,
                      height: 200,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '먼저, 번역이 필요한\n이미지를 올려주세요.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: ColorTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '이미지를 기반으로 학습 노트를 만들어드립니다. \n카메라 촬영도 가능합니다.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: const Color(0xFF969696), // #969696
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }


} 