import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../theme/tokens/ui_tokens.dart';
import '../../features/flashcard/flashcard_counter_badge.dart';
import '../services/authentication/user_preferences_service.dart';
import '../services/subscription/unified_subscription_manager.dart';
import '../../features/settings/settings_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/subscription_state.dart';

/// 공통 앱바 위젯
/// 모든 스크린에서 재사용할 수 있도록 설계된 커스터마이저블 앱바

class PikaAppBar extends StatefulWidget implements PreferredSizeWidget {
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
  factory PikaAppBar.home() {
    return PikaAppBar(
      showLogo: true,
      backgroundColor: UITokens.screenBackground,
      height: 124,
      isHome: true,
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
  State<PikaAppBar> createState() => _PikaAppBarState();
  
  @override
  Size get preferredSize {
    final double appBarHeight = height ?? toolbarHeight ?? kToolbarHeight;
    final double bottomExtent = bottom is PreferredSizeWidget 
        ? (bottom as PreferredSizeWidget).preferredSize.height 
        : 0.0;
    return Size.fromHeight(appBarHeight + bottomExtent);
  }
}

class _PikaAppBarState extends State<PikaAppBar> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isHome) {
      return _buildHomeAppBar(context);
    }

    // 앱바 컨텐츠
    AppBar appBar = AppBar(
      backgroundColor: widget.backgroundColor ?? Colors.transparent,
      elevation: widget.elevation ?? 0,
      centerTitle: widget.centerTitle,
      automaticallyImplyLeading: widget.automaticallyImplyLeading,
      titleSpacing: widget.showLogo ? 24.0 : 4.0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // 안드로이드용 (검정 아이콘)
        statusBarBrightness: Brightness.light, // iOS용 (밝은 배경 = 검정 아이콘)
      ),
      leading: widget.showBackButton
          ? IconButton(
              key: const Key('pika_app_bar_back_button'),
              icon: const Icon(Icons.arrow_back, color: ColorTokens.textSecondary),
              onPressed: widget.onBackPressed ?? () => Navigator.of(context).popUntil((route) => route.isFirst),
            )
          : widget.leading,
      title: _buildTitleWithPlanBadge(context),
      actions: widget.actions,
      bottom: widget.bottom != null
          ? PreferredSize(
              preferredSize: Size.fromHeight(widget.bottomHeight),
              child: widget.bottom!,
            )
          : widget.showBorder
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
    if (widget.currentPageIndex != null && widget.totalPages != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          appBar,
          SizedBox(height: widget.bottomHeight),
          _buildPageIndicator(),
        ],
      );
    }

    return Container(
      height: widget.preferredSize.height,
      child: appBar,
    );
  }

  Widget _buildHomeAppBar(BuildContext context) {
    return Container(
      height: 124, // 명시적으로 높이 설정
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        toolbarHeight: 124, // AppBar의 툴바 높이도 124로 설정
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark, // 안드로이드용 (검정 아이콘)
          statusBarBrightness: Brightness.light, // iOS용 (밝은 배경 = 검정 아이콘)
        ),
        title: Padding(
          padding: EdgeInsets.only(left: SpacingTokens.lg),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _loadHomeAppBarData(),
            builder: (context, snapshot) {
              final data = snapshot.data ?? {};
              final noteSpaceName = data['noteSpaceName'] as String? ?? '로딩 중...';
              final isPlanFree = data['isPlanFree'] as bool? ?? true;
              
              return _buildLogoTitle(noteSpaceName);
            },
          ),
        ),
        actions: [
          // 설정 버튼
          IconButton(
            icon: SvgPicture.asset(
              'assets/images/icon_profile.svg',
              width: SpacingTokens.profileIconSize,
              height: SpacingTokens.profileIconSize,
            ),
            onPressed: () => _navigateToSettings(context),
            tooltip: '설정',
          ),
          SizedBox(width: SpacingTokens.md),
        ],
      ),
    );
  }

  /// 홈 앱바 데이터 로드 (노트스페이스 이름, 플랜 정보)
  Future<Map<String, dynamic>> _loadHomeAppBarData() async {
    try {
      final userPreferences = UserPreferencesService();
      final unifiedManager = UnifiedSubscriptionManager();
      final results = await Future.wait([
        userPreferences.getDefaultNoteSpace(),
        unifiedManager.getSubscriptionEntitlements(),
      ]);
      final entitlements = results[1] as Map<String, dynamic>;
      return {
        'noteSpaceName': results[0] as String,
        'isPlanFree': !(entitlements.isPremium),
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('홈 앱바 데이터 로드 중 오류: $e');
      }
      return {
        'noteSpaceName': '노트스페이스',
        'isPlanFree': true,
      };
    }
  }

  /// 설정 화면으로 이동
  void _navigateToSettings(BuildContext context) {
    if (kDebugMode) {
      debugPrint('설정 화면으로 이동 시도');
    }
    try {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SettingsScreen(
            onLogout: () async {
              if (kDebugMode) {
                debugPrint('로그아웃 콜백 호출됨');
              }
              // 로그아웃 처리
              await FirebaseAuth.instance.signOut();
              // 홈 화면으로 돌아가기
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('설정 화면 이동 중 오류: $e');
      }
      // 오류 발생 시 사용자에게 알림
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('설정 화면 이동 중 오류가 발생했습니다: $e')),
      );
    }
  }

  Widget _buildTitleWithPlanBadge(BuildContext context) {
    // 설정 페이지인 경우 단순 타이틀만 표시
    if (widget.title != null && !widget.showLogo) {
      return Text(
        widget.title!,
        style: TypographyTokens.headline3.copyWith(
          color: ColorTokens.textPrimary,
        ),
      );
    }

    // 플랜 뱃지 등 PlanService 의존 부분 제거, noteSpaceName만 표시
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildLogoTitle(widget.noteSpaceName),
            ),
          ],
        ),
        if (widget.subtitle != null) ...[
          SizedBox(height: SpacingTokens.xs),
          widget.subtitle!,
        ],
      ],
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
        // 노트스페이스 이름만 단순 표시
        if (noteSpaceName != null)
          Row(
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
          '${widget.currentPageIndex} / ${widget.totalPages}',
          style: TypographyTokens.body2.copyWith(
            color: ColorTokens.textSecondary,
          ),
        ),
      ],
    );
  }

} 