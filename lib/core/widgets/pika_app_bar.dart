import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../theme/tokens/ui_tokens.dart';
import '../../widgets/flashcard_counter_badge.dart';
import '../services/common/plan_service.dart';

/// 공통 앱바 위젯
/// 모든 스크린에서 재사용할 수 있도록 설계된 커스터마이저블 앱바

class PikaAppBar extends StatelessWidget implements PreferredSizeWidget {
  // 공통 속성
  final String? title;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;
  final Widget? leading;
  final Color? backgroundColor;
  final bool centerTitle;
  final Widget? subtitle;
  final double? height;
  final bool showBackButton;
  final bool showLogo;
  final String? noteSpaceName;
  final bool showBorder;
  final Widget? bottom;
  final bool automaticallyImplyLeading;
  final double bottomHeight;
  
  // 플래시카드 카운터 - noteId가 sample-animal-book이 아닌 경우에만 표시
        
  final int? flashcardCount;
  final String? noteId;
  final VoidCallback? onFlashCardPressed;
  
  // 페이지 카운터 관련 속성
  final int? currentPageIndex;
  final int? totalPages;

  final VoidCallback? onSettingsPressed;
  final bool isHome;
  final double? elevation;
  final double? titleSpacing;
  final double? leadingWidth;
  final double? toolbarHeight;

  const PikaAppBar({
    Key? key,
    this.title,
    this.onBackPressed,
    this.actions,
    this.leading,
    this.backgroundColor,
    this.centerTitle = false,
    this.subtitle,
    this.height,
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
    this.bottomHeight = 16,
    this.onSettingsPressed,
    this.isHome = false,
    this.elevation,
    this.titleSpacing,
    this.leadingWidth,
    this.toolbarHeight,
  }) : super(key: key);

  /// 홈 스크린용 앱바 팩토리 생성자
  factory PikaAppBar.home({
    required String noteSpaceName,
    required VoidCallback onSettingsPressed,
  }) {
    return PikaAppBar(
      showLogo: true,
      noteSpaceName: noteSpaceName,
      backgroundColor: UITokens.screenBackground,
      height: 108,
      actions: [
        Padding(
          padding: EdgeInsets.only(right: SpacingTokens.md),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                debugPrint('설정 버튼 클릭됨 - InkWell');
                onSettingsPressed();
              },
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(12),
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
    Color backgroundColor = UITokens.screenBackground,
    String? noteId,
    List<dynamic>? flashcards,
    String? sampleNoteTitle,
  }) {
    return PikaAppBar(
      title: title,
      showBackButton: true,
      onBackPressed: onBackPressed,
      automaticallyImplyLeading: true,
      height: 108,
      backgroundColor: backgroundColor,
      showLogo: false,  // 로고를 표시하지 않음
      centerTitle: false,  // 타이틀을 왼쪽 정렬
      actions: [
        // 플래시카드 카운터 - noteId가 sample-animal-book이 아닌 경우에만 표시
        if (noteId != "sample-animal-book")
        GestureDetector(
          onTap: onFlashcardTap,
          child: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FlashcardCounterBadge(
              count: flashcardCount,
              noteId: noteId,
              flashcards: flashcards,
              sampleNoteTitle: sampleNoteTitle,
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
      height: 108,
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
      height: 108,
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
    if (isHome) {
      return _buildHomeAppBar(context);
    }

    // 앱바 컨텐츠
    AppBar appBar = AppBar(
      backgroundColor: backgroundColor ?? Colors.transparent,
      elevation: elevation ?? 0,
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
      title: _buildTitleWithPlanBadge(context),
      actions: actions,
      bottom: bottom != null
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

    // 페이지 인디케이터가 있는 경우
    if (currentPageIndex != null && totalPages != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          appBar,
          SizedBox(height: bottomHeight),
          _buildPageIndicator(),
        ],
      );
    }

    return Container(
      height: preferredSize.height,
      child: appBar,
    );
  }

  Widget _buildHomeAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Padding(
        padding: EdgeInsets.only(left: SpacingTokens.lg),
        child: FutureBuilder<String>(
          future: PlanService().getCurrentPlanType(),
          builder: (context, snapshot) {
            final isPlanFree = snapshot.data == PlanService.PLAN_FREE;
            
            return Row(
              children: [
                Expanded(
                  child: Text(
                    noteSpaceName ?? '',
                    style: TypographyTokens.headline3.copyWith(
                      color: ColorTokens.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        if (onSettingsPressed != null)
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: ColorTokens.textPrimary,
              size: SpacingTokens.iconSizeMedium,
            ),
            onPressed: onSettingsPressed,
          ),
        SizedBox(width: SpacingTokens.md),
      ],
    );
  }

  Widget _buildTitleWithPlanBadge(BuildContext context) {
    // 설정 페이지인 경우 단순 타이틀만 표시
    if (title != null && !showLogo) {
      return Text(
        title!,
        style: TypographyTokens.headline3.copyWith(
          color: ColorTokens.textPrimary,
        ),
      );
    }

    return FutureBuilder<String>(
      future: PlanService().getCurrentPlanType(),
      builder: (context, snapshot) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildLogoTitle(noteSpaceName),
                ),
              ],
            ),
            if (subtitle != null) ...[
              SizedBox(height: SpacingTokens.xs),
              subtitle!,
            ],
          ],
        );
      },
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
          FutureBuilder<String>(
            future: PlanService().getCurrentPlanType(),
            builder: (context, snapshot) {
              final isPlanFree = snapshot.data == PlanService.PLAN_FREE;
              
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      noteSpaceName,
                      style: TypographyTokens.headline3.copyWith(
                        color: ColorTokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  // 페이지 인디케이터 빌드
  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$currentPageIndex / $totalPages',
          style: TypographyTokens.body2.copyWith(
            color: ColorTokens.textSecondary,
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize {
    final double appBarHeight = height ?? toolbarHeight ?? kToolbarHeight;
    final double bottomExtent = bottom is PreferredSizeWidget 
        ? (bottom as PreferredSizeWidget).preferredSize.height 
        : 0.0;
    return Size.fromHeight(appBarHeight + bottomExtent);
  }
} 