import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  final bool automaticallyImplyLeading;
  final double bottomHeight;
  final double progress;
  
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
    this.backgroundColor = Colors.transparent,
    this.centerTitle = false,
    this.subtitle,
    this.height = 96,
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
    this.automaticallyImplyLeading = true,
    this.bottomHeight = 2,
    this.progress = 0,
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
      height: 100,
      actions: [
        Padding(
          padding: EdgeInsets.only(right:SpacingTokens.md, bottom:SpacingTokens.md),
          child: GestureDetector(
            onTap: () {
              debugPrint('설정 버튼 클릭됨 - GestureDetector');
              onSettingsPressed();
            },
            child: Container(
              width: 48,  // 더 넓은 터치 영역
              height: 48, // 더 넓은 터치 영역
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/images/icon_profile.svg',
                  width: SpacingTokens.profileIconSize,
                  height: SpacingTokens.profileIconSize,
                  placeholderBuilder: (context) => Icon(
                    Icons.person,
                    color: ColorTokens.secondary,
                    size: SpacingTokens.profileIconSize,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 노트 상세 화면용 앱바
  factory PikaAppBar.noteDetail({
    required String title,
    required int currentPage,
    required int totalPages,
    required int flashcardCount,
    required VoidCallback onMorePressed,
    required VoidCallback onFlashcardTap,
    VoidCallback? onBackPressed,
  }) {
    return PikaAppBar(
      title: title,
      showBackButton: true,
      onBackPressed: onBackPressed,
      automaticallyImplyLeading: true,
      height: 96,
      actions: [
        // 플래시카드 카운터
        GestureDetector(
          onTap: onFlashcardTap,
          child: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FlashcardCounterBadge(
              count: flashcardCount,
            ),
          ),
        ),
        
        // 더보기 버튼
        IconButton(
          icon: const Icon(
            Icons.more_vert,
            color: ColorTokens.textGrey,
            size: 24,
          ),
          padding: const EdgeInsets.only(right: 8),
          constraints: const BoxConstraints(),
          tooltip: '더 보기',
          onPressed: onMorePressed,
        ),
      ],
      showBorder: false,
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
      height: 96,
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
      height: 96,
      actions: totalCards > 0 ? [
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Center(
            child: Text(
              'card ${currentCardIndex + 1} / $totalCards',
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ] : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 앱바 컨텐츠
    AppBar appBar = AppBar(
      backgroundColor: backgroundColor,
      elevation: 0,
      centerTitle: centerTitle,
      automaticallyImplyLeading: automaticallyImplyLeading,
      titleSpacing: showLogo ? 24.0 : 4.0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // 안드로이드용 (검정 아이콘)
        statusBarBrightness: Brightness.light, // iOS용 (밝은 배경 = 검정 아이콘)
      ),
      leading: showBackButton
          ? IconButton(
              key: const Key('pika_app_bar_back_button'),
              icon: const Icon(Icons.arrow_back, color: ColorTokens.textSecondary),
              onPressed: onBackPressed ?? () => Navigator.of(context).popUntil((route) => route.isFirst),
            )
          : leading,
      title: title != null
          ? Text(
              title!,
              style: TypographyTokens.headline3.copyWith(
                color: ColorTokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : showLogo
              ? _buildLogoTitle(noteSpaceName)
              : null,
      actions: actions,
      bottom: progress > 0 
          ? PreferredSize(
              preferredSize: Size.fromHeight(bottomHeight),
              child: _buildProgressBar(context, progress),
            )
          : bottom != null
              ? PreferredSize(
                  preferredSize: Size.fromHeight(bottomHeight),
                  child: bottom!,
                )
              : showBorder
                  ? PreferredSize(
                      preferredSize: Size.fromHeight(1.0),
                      child: Container(
                        height: 1.0,
                        color: Colors.grey.withOpacity(0.1),
                      ),
                    )
                  : null,
    );

    return Container(
      height: preferredSize.height,
      child: appBar,
    );
  }

  // 로고와 노트스페이스 이름 빌드
  Widget _buildLogoTitle(String? noteSpaceName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 앱 로고
        Container(
          alignment: Alignment.centerLeft,
          child: SvgPicture.asset(
            'assets/images/pikabook_textlogo_primary.svg',
            width: SpacingTokens.appLogoWidth * 1.2,
            height: SpacingTokens.appLogoHeight * 1.2,
            placeholderBuilder: (context) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pikabook',
                  style: TypographyTokens.body1En.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ColorTokens.primary,
                    fontSize: 18,
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
            noteSpaceName,
            style: TypographyTokens.headline3.copyWith(
              color: ColorTokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  /// 프로그레스 바 위젯 빌드
  Widget _buildProgressBar(BuildContext context, double progress) {
    // progress는 0.0 ~ 1.0 사이 값
    final double clampedProgress = progress.clamp(0.0, 1.0);
    
    return Stack(
      children: [
        // 배경 (회색 배경)
        Container(
          width: double.infinity,
          height: bottomHeight,
          color: ColorTokens.divider,
        ),
        // 진행 상태 (오렌지색)
        Container(
          width: MediaQuery.of(context).size.width * clampedProgress,
          height: bottomHeight,
          color: ColorTokens.primary,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(height);
} 