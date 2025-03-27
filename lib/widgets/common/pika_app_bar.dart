import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../dot_loading_indicator.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';
import '../../theme/tokens/ui_tokens.dart';
import '../flashcard_counter_badge.dart';

/// 공통 앱바 위젯
/// 모든 스크린에서 재사용할 수 있도록 설계된 커스터마이저블 앱바
class PikaAppBar extends StatelessWidget implements PreferredSizeWidget {
  // 공통 속성
  final String? title;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;
  final Widget? leading;
  final Color backgroundColor;
  final bool centerTitle;
  final Widget? subtitle;
  final double height;
  final bool showBackButton;
  final bool showLogo;
  final String? noteSpaceName;
  final bool showBorder;
  final Widget? bottom;
  
  // 플래시카드 카운터 관련 속성
  final int? flashcardCount;
  final String? noteId;
  final VoidCallback? onFlashCardPressed;
  
  // 페이지 카운터 관련 속성
  final int? currentPageIndex;
  final int? totalPages;

  const PikaAppBar({
    Key? key,
    this.title,
    this.onBackPressed,
    this.actions,
    this.leading,
    this.backgroundColor = Colors.white,
    this.centerTitle = false,
    this.subtitle,
    this.height = 70,
    this.showBackButton = false,
    this.showLogo = false,
    this.noteSpaceName,
    this.showBorder = false,
    this.bottom,
    this.flashcardCount,
    this.noteId,
    this.onFlashCardPressed,
    this.currentPageIndex,
    this.totalPages,
  }) : super(key: key);

  /// 홈 스크린용 앱바 팩토리 생성자
  factory PikaAppBar.home({
    required String noteSpaceName,
    required VoidCallback onSettingsPressed,
  }) {
    return PikaAppBar(
      showLogo: true,
      noteSpaceName: noteSpaceName,
      backgroundColor: UITokens.homeBackground,
      height: 80, // HomeScreenAppBar와 일치시킴
      actions: [
        Padding(
          padding: EdgeInsets.only(right: SpacingTokens.md),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onSettingsPressed,
              splashColor: ColorTokens.primary.withOpacity(0.1),
              highlightColor: ColorTokens.primary.withOpacity(0.05),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                  width: SpacingTokens.iconSizeMedium,
                  height: SpacingTokens.iconSizeMedium,
                  child: SvgPicture.asset(
                    'assets/images/icon_profile.svg',
                    width: SpacingTokens.iconSizeMedium,
                    height: SpacingTokens.iconSizeMedium,
                    placeholderBuilder: (context) => Icon(
                      Icons.person,
                      color: ColorTokens.secondary,
                      size: SpacingTokens.iconSizeMedium,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 노트 상세 화면용 앱바 팩토리 생성자
  factory PikaAppBar.noteDetail({
    required String title,
    required VoidCallback onBackPressed,
    required VoidCallback onShowMoreOptions,
    required VoidCallback onFlashCardPressed,
    required int flashcardCount,
    
    String? noteId,
    int currentPageIndex = 0,
    int totalPages = 0,
  }) {
    return PikaAppBar(
      title: title,
      showBackButton: true,
      onBackPressed: onBackPressed,
      flashcardCount: flashcardCount,
      noteId: noteId,
      onFlashCardPressed: onFlashCardPressed,
      currentPageIndex: currentPageIndex,
      totalPages: totalPages,
      height: 80,
      actions: [
        if (totalPages > 0)
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Text(
                'page ${currentPageIndex + 1} / $totalPages',
                style: TypographyTokens.caption.copyWith(
                  color: ColorTokens.textSecondary,
                ),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(
            Icons.more_vert,
            color: ColorTokens.textGrey,
          ),
          onPressed: onShowMoreOptions,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: '더 보기',
        ),
      ],
      bottom: totalPages > 0 ? _buildProgressBar(currentPageIndex, totalPages) : null,
    );
  }

  /// 설정 화면용 앱바 팩토리 생성자
  factory PikaAppBar.settings({
    required VoidCallback onBackPressed,
  }) {
    return PikaAppBar(
      title: '설정',
      showBackButton: true,
      onBackPressed: onBackPressed,
    );
  }

  /// 플래시카드 화면용 앱바 팩토리 생성자
  factory PikaAppBar.flashcard({
    required VoidCallback onBackPressed,
    int currentCardIndex = 0,
    int totalCards = 0,
  }) {
    return PikaAppBar(
      title: '플래시카드',
      showBackButton: true,
      onBackPressed: onBackPressed,
      actions: totalCards > 0 ? [
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Center(
            child: Text(
              'card ${currentCardIndex + 1} / $totalCards',
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.textSecondary,
              ),
            ),
          ),
        ),
      ] : null,
    );
  }

  // 진행 상태 표시바 생성 함수
  static Widget _buildProgressBar(int currentPageIndex, int totalPages) {
    return SizedBox(
      height: 4, // 높이를 4px로 증가
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final progressWidth = totalPages > 0 
            ? (currentPageIndex + 1) / totalPages * screenWidth 
            : 0.0;
          
          return Stack(
            children: [
              // 배경 바
              Container(
                width: double.infinity,
                height: 4, // 높이를 4px로 증가
                color: ColorTokens.divider,
              ),
              // 진행 바
              Container(
                width: progressWidth,
                height: 4, // 높이를 4px로 증가
                color: ColorTokens.primary,
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 상태 표시줄 스타일 설정
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );

    final String? pageNumberText = (currentPageIndex != null && totalPages != null && totalPages! > 0)
        ? 'page ${currentPageIndex! + 1} / $totalPages'
        : null;

    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // AppBar 메인 컨텐츠
          SizedBox(
            height: height - (bottom != null ? 4 : 0), // 프로그레스 바가 있으면 높이 조정
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 왼쪽 부분: 뒤로가기 버튼, 로고 또는 제목
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 뒤로가기 버튼 (옵션)
                        if (showBackButton)
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_rounded,
                              color: Colors.black,
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
                          ),
                        if (showBackButton)
                          const SizedBox(width: 4),
                        
                        // 커스텀 leading 위젯
                        if (leading != null)
                          leading!,
                        
                        // 로고 표시 (홈 스크린)
                        if (showLogo)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 앱 로고
                                Container(
                                  alignment: Alignment.centerLeft,
                                  child: SvgPicture.asset(
                                    'assets/images/pikabook_textlogo_primary.svg',
                                    width: SpacingTokens.appLogoWidth,
                                    height: SpacingTokens.appLogoHeight,
                                    placeholderBuilder: (context) => Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.menu_book,
                                          color: ColorTokens.primary,
                                          size: SpacingTokens.iconSizeSmall,
                                        ),
                                        SizedBox(width: SpacingTokens.xs),
                                        Text(
                                          'Pikabook',
                                          style: TypographyTokens.body1En.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: ColorTokens.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(height: SpacingTokens.xs),
                                // 노트 스페이스 이름
                                if (noteSpaceName != null)
                                  Text(
                                    noteSpaceName!,
                                    style: TypographyTokens.headline3.copyWith(
                                      color: ColorTokens.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        
                        // 제목 (일반 스크린)
                        if (!showLogo && title != null)
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 타이틀
                                Flexible(
                                  child: Text(
                                    title!,
                                    style: TypographyTokens.headline3.copyWith(
                                      color: ColorTokens.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                
                                // 페이지 정보 (노트 상세)
                                if (pageNumberText != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: Text(
                                      pageNumberText,
                                      style: TypographyTokens.body2En.copyWith(
                                        color: ColorTokens.textGrey,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // 오른쪽 부분: 액션 버튼들
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 플래시카드 카운터 (노트 상세)
                      if (flashcardCount != null && flashcardCount! > 0)
                        GestureDetector(
                          onTap: onFlashCardPressed,
                          child: FlashcardCounterBadge(
                            count: flashcardCount!,
                            noteId: noteId,
                          ),
                        ),
                      
                      if (flashcardCount != null)
                        const SizedBox(width: 8),
                      
                      // 추가 액션 버튼들
                      if (actions != null)
                        ...actions!,
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // 하단 위젯 (프로그레스 바 등)
          if (bottom != null)
            bottom!,
        ],
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(height);
} 