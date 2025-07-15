import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../core/utils/language_constants.dart';
import '../../core/widgets/loading_experience.dart';
import '../../../core/widgets/pika_button.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/usage_dialog.dart';
import '../../core/widgets/upgrade_modal.dart';
import '../../core/widgets/edit_dialog.dart';
import '../../core/utils/test_data_generator.dart';
import '../../core/services/common/banner_manager.dart';
import '../../core/services/subscription/unified_subscription_manager.dart';
import '../debug/payment_debug_screen.dart';

import 'settings_view_model.dart';
import 'package:flutter/foundation.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onLogout;

  const SettingsScreen({
    Key? key,
    required this.onLogout,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = SettingsViewModel();
    _viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorTokens.background,
      appBar: PikaAppBar.settings(
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      body: LoadingExperience(
        loadingMessage: '설정 로딩 중...',
        loadData: () async {
          await _viewModel.initialize();
        },
        contentBuilder: (context) => _buildProfileContent(),
      ),
    );
  }

  Widget _buildProfileContent() {
    final String displayName = _viewModel.currentUser?.displayName ?? '사용자';
    final String email = _viewModel.currentUser?.email ?? '이메일 없음';
    final String? photoUrl = _viewModel.currentUser?.photoURL;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          
          // 1. 프로필 정보 섹션
          _buildSectionTitle('프로필'),
          const SizedBox(height: 12),
          _buildProfileCard(displayName, email, photoUrl),
          
          const SizedBox(height: 16),
          
          // 로그아웃 버튼
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            child: PikaButton(
              text: '로그아웃',
              variant: PikaButtonVariant.outline,
              onPressed: () {
                widget.onLogout();
                Navigator.pop(context);
              },
              isFullWidth: true,
            ),
          ),
          
          const SizedBox(height: 32),
          
          // 현재 사용 중인 플랜 정보 섹션
                      _buildSectionTitle('내 플랜'),
            const SizedBox(height: 12),
            _buildPlanCard(isLoading: !_viewModel.isPlanLoaded),
          
          const SizedBox(height: 32),
          
          // 2. 노트 설정 섹션
          _buildSectionTitle('노트 설정'),
          const SizedBox(height: 12),
          
          // 학습자 이름 설정
          _buildSettingItem(
            title: '학습자 이름',
            value: _viewModel.userName,
            onTap: _showUserNameDialog,
          ),
          
          const SizedBox(height: 8),
          
          // 노트 스페이스 이름 설정
          _buildSettingItem(
            title: '노트스페이스 이름',
            value: _viewModel.noteSpaceName,
            onTap: _showNoteSpaceNameDialog,
          ),
          
          const SizedBox(height: 8),
          
          // 원문 언어 설정
          _buildSettingItem(
            title: '원문 언어',
            value: SourceLanguage.getName(_viewModel.sourceLanguage),
            onTap: _showSourceLanguageDialog,
          ),
          
          const SizedBox(height: 8),
          
          // 번역 언어 설정
          _buildSettingItem(
            title: '번역 언어',
            value: TargetLanguage.getName(_viewModel.targetLanguage),
            onTap: _showTargetLanguageDialog,
          ),
          
          const SizedBox(height: 8),
          
          // 텍스트 처리 모드 설정
          _buildSettingItem(
            title: '텍스트 처리 모드',
            value: _viewModel.useSegmentMode ? '문장 단위' : '문단 단위',
            onTap: _showTextProcessingModeDialog,
          ),
          
          const SizedBox(height: 32),
          
          // 디버그 전용 섹션 (테스트 데이터 생성)
          if (kDebugMode) ...[
            _buildSectionTitle('🧪 개발자 도구'),
            const SizedBox(height: 12),
            
            // 테스트 계정 생성 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              child: PikaButton(
                text: '🎯 모든 테스트 계정 생성',
                variant: PikaButtonVariant.primary,
                onPressed: _generateAllTestAccounts,
                isFullWidth: true,
              ),
            ),
            
            // 테스트 계정 목록 출력 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              child: PikaButton(
                text: '📋 테스트 계정 목록 출력',
                variant: PikaButtonVariant.outline,
                onPressed: () => TestDataGenerator.printTestAccounts(),
                isFullWidth: true,
              ),
            ),
            
            // 배너 닫기 기록 초기화 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              child: PikaButton(
                text: '🔄 배너 닫기 기록 초기화',
                variant: PikaButtonVariant.outline,
                onPressed: _resetBannerStates,
                isFullWidth: true,
              ),
            ),
            
            // Payment Debug 화면 이동 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              child: PikaButton(
                text: '🔍 Payment Debug 화면',
                variant: PikaButtonVariant.outline,
                onPressed: _navigateToPaymentDebug,
                isFullWidth: true,
              ),
            ),
            
            // 구독 디버그 헬퍼 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              child: PikaButton(
                text: '🔍 구독 상태 전체 진단',
                variant: PikaButtonVariant.text,
                onPressed: _runSubscriptionDebug,
                isFullWidth: true,
              ),
            ),
            
            const SizedBox(height: 32),
          ],
          
          // 3. 계정 관리 섹션
          _buildSectionTitle('계정관리'),
          const SizedBox(height: 12),
          
          // 회원 탈퇴 버튼
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            child: PikaButton(
              text: '회원 탈퇴',
              variant: PikaButtonVariant.warning,
              onPressed: () => _handleAccountDeletion(context),
              isFullWidth: true,
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // 프로필 카드 위젯
  Widget _buildProfileCard(String displayName, String email, String? photoUrl) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(SpacingTokens.sm),
      decoration: BoxDecoration(
        color: ColorTokens.surface,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
      ),
      child: Row(
        children: [
          // 프로필 이미지
          CircleAvatar(
            radius: SpacingTokens.iconSizeMedium,
            backgroundColor: ColorTokens.greyLight,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null
                ? Icon(Icons.person, 
                    size: SpacingTokens.iconSizeMedium, 
                    color: ColorTokens.greyMedium)
                : null,
          ),
          SizedBox(width: SpacingTokens.md),
          
          // 사용자 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TypographyTokens.buttonEn,
                ),
                SizedBox(height: SpacingTokens.xsHalf),
                Text(
                  email,
                  style: TypographyTokens.captionEn.copyWith(
                    color: ColorTokens.textPrimary.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // 섹션 제목 위젯
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TypographyTokens.button.copyWith(
        color: ColorTokens.textSecondary,
      ),
    );
  }
  
  // 설정 항목 위젯
  Widget _buildSettingItem({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
        child: Container(
          width: double.infinity,
          height: SpacingTokens.buttonHeight + SpacingTokens.sm,
          padding: EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
            vertical: SpacingTokens.sm
          ),
          decoration: BoxDecoration(
            color: ColorTokens.surface,
            borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TypographyTokens.captionEn.copyWith(
                      color: ColorTokens.textSecondary,
                    ),
                  ),
                  Text(
                    value,
                    style: TypographyTokens.body2,
                  ),
                ],
              ),
              SvgPicture.asset(
                'assets/images/icon_arrow_right.svg',
                width: SpacingTokens.iconSizeSmall + SpacingTokens.xs,
                height: SpacingTokens.iconSizeSmall + SpacingTokens.xs,
                colorFilter: const ColorFilter.mode(
                  ColorTokens.secondary,
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // 플랜 카드 위젯 (로딩/정보 통합)
  Widget _buildPlanCard({bool isLoading = false}) {
    return GestureDetector(
      onTap: isLoading ? null : () async {
        // 플랜 정보 새로고침
        await _viewModel.refreshPlanInfo();
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 플랜 이름 또는 로딩 스켈레톤
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isLoading)
                        Container(
                          width: 80,
                          height: 20,
                          decoration: BoxDecoration(
                            color: ColorTokens.greyLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )
                      else ...[
                        Text(
                          _viewModel.planName,
                          style: TypographyTokens.body2.copyWith(
                            color: ColorTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '탭하여 새로고침',
                          style: TypographyTokens.caption.copyWith(
                            color: ColorTokens.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // 사용량 확인 버튼
                Opacity(
                  opacity: isLoading ? 0.5 : 1.0,
                  child: GestureDetector(
                    onTap: isLoading ? null : _showUsageDialog,
                    child: Row(
                      children: [
                        Text(
                          '사용량 확인',
                          style: TypographyTokens.body2.copyWith(
                            color: ColorTokens.textPrimary,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        SizedBox(width: SpacingTokens.md),
                        SvgPicture.asset(
                          'assets/images/icon_arrow_right.svg',
                          width: 20,
                          height: 20,
                          colorFilter: const ColorFilter.mode(
                            ColorTokens.secondary,
                            BlendMode.srcIn,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            // 🎯 구독 상태별 CTA 버튼 표시 (로딩 중이 아닐 때만)
            if (!isLoading && _viewModel.ctaButtonText.isNotEmpty) ...[
              SizedBox(height: SpacingTokens.md),
              PikaButton(
                text: _viewModel.ctaButtonText,
                variant: _viewModel.ctaButtonEnabled 
                    ? PikaButtonVariant.primary 
                    : PikaButtonVariant.outline,
                size: PikaButtonSize.small,
                onPressed: _viewModel.ctaButtonEnabled ? _handleCTAButtonPressed : null,
                isFullWidth: true,
              ),
              
              // 🎯 서브텍스트 표시 (있는 경우만)
              if (_viewModel.ctaSubtext.isNotEmpty) ...[
                SizedBox(height: SpacingTokens.xs),
                Text(
                  _viewModel.ctaSubtext,
                  style: TypographyTokens.caption.copyWith(
                    color: ColorTokens.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
  
  /// 🎯 CTA 버튼 클릭 처리
  void _handleCTAButtonPressed() {
    if (_viewModel.ctaButtonText.contains('문의')) {
      // "사용량 추가 문의" 버튼인 경우
      _contactSupport();
    } else if (_viewModel.ctaButtonText.contains('업그레이드')) {
      // "프리미엄으로 업그레이드" 버튼인 경우
      _showUpgradeModal();
    }
    // disabled 버튼들은 onPressed가 null이므로 여기에 도달하지 않음
  }
  
  // 사용량 다이얼로그 표시
  Future<void> _showUsageDialog() async {
    if (kDebugMode) {
      print('📊 사용량 확인 버튼 클릭 - 사용량 데이터 로드 시작');
      print('📊 프리미엄 쿼터 사용: ${_viewModel.shouldUsePremiumQuota}');
      print('📊 플랜 제한: ${_viewModel.planLimits}');
    }
    
    if (context.mounted) {
      await UsageDialog.show(
        context,
        limitStatus: null,
        usagePercentages: null,
        onContactSupport: _contactSupport,
        shouldUsePremiumQuota: _viewModel.shouldUsePremiumQuota,
        planLimits: _viewModel.planLimits,
      );
    }
  }
  
  // 문의하기 기능 (향후 인앱 구매로 전환 예정)
  void _contactSupport() async {
    final success = await _viewModel.contactSupport();
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('문의가 등록되었습니다.'),
            backgroundColor: ColorTokens.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('문의 등록 중 오류가 발생했습니다.'),
            backgroundColor: ColorTokens.error,
          ),
        );
      }
    }
  }
  
  // 학습자 이름 설정 다이얼로그
  Future<void> _showUserNameDialog() async {
    showDialog<void>(
      context: context,
      builder: (context) => EditDialog.forUserName(
        currentName: _viewModel.userName,
        onNameUpdated: (newName) async {
          if (newName.isNotEmpty) {
            await _viewModel.updateUserName(newName);
          }
        },
      ),
    );
  }
  
  // 노트 스페이스 이름 변경 다이얼로그
  Future<void> _showNoteSpaceNameDialog() async {
    showDialog<void>(
      context: context,
      builder: (context) => EditDialog.forNoteSpace(
        currentName: _viewModel.noteSpaceName,
        onNameUpdated: (newName) async {
          if (newName.isNotEmpty) {
            final success = await _viewModel.updateNoteSpaceName(newName);
            if (mounted) {
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '노트 스페이스 이름이 변경되었습니다.',
                      style: TypographyTokens.caption.copyWith(
                        color: ColorTokens.textLight,
                      ),
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '노트 스페이스 이름 변경 중 오류가 발생했습니다.',
                      style: TypographyTokens.caption.copyWith(
                        color: ColorTokens.textLight,
                      ),
                    ),
                    backgroundColor: ColorTokens.error,
                  ),
                );
              }
            }
          }
        },
      ),
    );
  }
  
  // 원문 언어 설정 다이얼로그
  Future<void> _showSourceLanguageDialog() async {
    final sourceLanguages = [...SourceLanguage.SUPPORTED, ...SourceLanguage.FUTURE_SUPPORTED];
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: Text('원문 언어 설정', style: TypographyTokens.subtitle2),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sourceLanguages.length,
            itemBuilder: (context, index) {
              final language = sourceLanguages[index];
              final bool isFutureSupported = SourceLanguage.FUTURE_SUPPORTED.contains(language);
              
              return RadioListTile<String>(
                title: Text(
                  SourceLanguage.getName(language),
                  style: TypographyTokens.body2,
                ),
                subtitle: isFutureSupported 
                    ? Text(
                        '향후 지원 예정',
                        style: TypographyTokens.caption.copyWith(
                          color: ColorTokens.textPrimary,
                        ),
                      )
                    : null,
                value: language,
                groupValue: _viewModel.sourceLanguage,
                activeColor: ColorTokens.primary,
                onChanged: isFutureSupported 
                    ? null 
                    : (value) {
                        Navigator.pop(context, value);
                      },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '취소',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (result != null) {
      await _viewModel.updateSourceLanguage(result);
    }
  }
  
  // 번역 언어 설정 다이얼로그
  Future<void> _showTargetLanguageDialog() async {
    final targetLanguages = [...TargetLanguage.SUPPORTED, ...TargetLanguage.FUTURE_SUPPORTED];
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: Text('번역 언어 설정', style: TypographyTokens.subtitle2),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: targetLanguages.length,
            itemBuilder: (context, index) {
              final language = targetLanguages[index];
              final bool isFutureSupported = TargetLanguage.FUTURE_SUPPORTED.contains(language);
              
              return RadioListTile<String>(
                title: Text(
                  TargetLanguage.getName(language),
                  style: TypographyTokens.body2,
                ),
                subtitle: isFutureSupported 
                    ? Text(
                        '향후 지원 예정',
                        style: TypographyTokens.caption.copyWith(
                          color: ColorTokens.textPrimary,
                        ),
                      )
                    : null,
                value: language,
                groupValue: _viewModel.targetLanguage,
                activeColor: ColorTokens.primary,
                onChanged: isFutureSupported 
                    ? null 
                    : (value) {
                        Navigator.pop(context, value);
                      },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '취소',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (result != null) {
      await _viewModel.updateTargetLanguage(result);
    }
  }
  
  // 텍스트 처리 모드 설정 다이얼로그
  Future<void> _showTextProcessingModeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: Text('텍스트 처리 모드 설정', style: TypographyTokens.subtitle2),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<bool>(
              title: Text(
                '문장 단위',
                style: TypographyTokens.body2,
              ),
              subtitle: Text(
                '문장별로 분리하여 번역하고 발음을 제공합니다.',
                style: TypographyTokens.caption.copyWith(
                  color: ColorTokens.textSecondary,
                ),
              ),
              value: true,
              groupValue: _viewModel.useSegmentMode,
              activeColor: ColorTokens.primary,
              onChanged: (value) => Navigator.pop(context, value),
            ),
            RadioListTile<bool>(
              title: Text(
                '문단 단위',
                style: TypographyTokens.body2,
              ),
              subtitle: Text(
                '문단 단위로 번역해 문맥에 맞는 번역을 제공합니다.',
                style: TypographyTokens.caption.copyWith(
                  color: ColorTokens.textSecondary,
                ),
              ),
              value: false,
              groupValue: _viewModel.useSegmentMode,
              activeColor: ColorTokens.primary,
              onChanged: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '취소',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (result != null) {
      final success = await _viewModel.updateTextProcessingMode(result);
      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '텍스트 처리 모드가 변경되었습니다. 새로 만드는 노트에 적용됩니다.',
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.textLight,
              ),
            ),
          ),
        );
      }
    }
  }
  
  // 계정 탈퇴 기능 구현
  /// 테스트 계정 생성 핸들러 (디버그 전용)
  Future<void> _generateAllTestAccounts() async {
    if (!kDebugMode) return;
    
    try {
      // 로딩 표시
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      await TestDataGenerator.generateAllTestAccounts();
      
      // 로딩 닫기
      if (mounted) Navigator.of(context).pop();
      
      // 성공 메시지
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 모든 테스트 계정이 생성되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
    } catch (e) {
      // 로딩 닫기
      if (mounted) Navigator.of(context).pop();
      
      // 에러 메시지
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 테스트 계정 생성 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleAccountDeletion(BuildContext context) async {
    // 1. 재인증 필요 여부 확인
    final needsReauth = await _viewModel.isReauthenticationRequired();
    
    if (needsReauth) {
      // 재인증이 필요한 경우: 재인증 안내 모달
      await _showReauthRequiredDialog(context);
    } else {
      // 재인증이 불필요한 경우: 경고 메시지 후 바로 탈퇴 처리
      await _showWarningAndDelete(context);
    }
  }
  
  // 재인증 필요 안내 모달
  Future<void> _showReauthRequiredDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: Text(
          '회원 탈퇴',
          style: TypographyTokens.subtitle2.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ColorTokens.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ColorTokens.warning.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.security,
                        size: 16,
                        color: ColorTokens.warning,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '보안 인증 필요',
                        style: TypographyTokens.caption.copyWith(
                          color: ColorTokens.warning,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '탈퇴하시려면 보안을 위해 재인증이 필요합니다.\n로그아웃 후 다시 로그인해주세요.',
                    style: TypographyTokens.caption.copyWith(
                      color: ColorTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: Text(
              '취소',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'logout'),
            child: Text(
              '로그아웃',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (result == 'logout') {
      // 로그아웃 처리
      widget.onLogout();
      Navigator.pop(context);
    }
  }
  
  // 경고 메시지 후 탈퇴 처리 (재인증 불필요한 경우)
  Future<void> _showWarningAndDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: Text(
          '회원 탈퇴',
          style: TypographyTokens.subtitle2.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '정말로 회원 탈퇴하시겠습니까?',
              style: TypographyTokens.body2,
            ),
            const SizedBox(height: 12),
            Text(
              '• 회원 탈퇴 시 모든 노트와 데이터가 삭제됩니다.',
              style: TypographyTokens.body2.copyWith(
                color: ColorTokens.textPrimary,
              ),
            ),
            Text(
              '• 이 작업은 되돌릴 수 없습니다.',
              style: TypographyTokens.body2.copyWith(
                color: ColorTokens.textPrimary,
              ),
            ),
            Text(
              '• 탈퇴 후 환불 및 결제 문의 대응을 위해, 구독 정보는 90일간 보존 후 자동 삭제됩니다.',
              style: TypographyTokens.body2.copyWith(
                color: ColorTokens.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '취소',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '탈퇴하기',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    // 탈퇴 처리 실행
    await _executeAccountDeletion(context);
  }
  
  // 실제 탈퇴 처리 실행
  Future<void> _executeAccountDeletion(BuildContext context) async {
    try {
      // 먼저 스낵바 표시 (Firebase 인증 상태 변경 전에)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '계정을 삭제하고 있습니다...',
              style: TypographyTokens.caption.copyWith(
                color: Colors.white,
              ),
            ),
            backgroundColor: ColorTokens.snackbarBg,
            behavior: SnackBarBehavior.fixed,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      // 스낵바가 표시될 시간 확보
      await Future.delayed(Duration(milliseconds: 500));
      
      final success = await _viewModel.deleteAccount();
      
      if (mounted && success) {
        // 탈퇴 성공 메시지
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '계정이 성공적으로 삭제되었습니다.',
              style: TypographyTokens.caption.copyWith(
                color: Colors.white,
              ),
            ),
            backgroundColor: ColorTokens.success,
            behavior: SnackBarBehavior.fixed,
            duration: Duration(seconds: 2),
          ),
        );
        
        // 명시적으로 로그아웃 처리 (Firebase 상태 변경만으로는 불충분)
        await Future.delayed(Duration(milliseconds: 500));
        if (mounted) {
          widget.onLogout(); // 로그아웃 콜백 호출
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString(),
              style: TypographyTokens.caption.copyWith(
                color: Colors.white,
              ),
            ),
            backgroundColor: ColorTokens.error,
            behavior: SnackBarBehavior.fixed,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // 🔄 배너 닫기 기록 초기화 (테스트용)
  Future<void> _resetBannerStates() async {
    try {
      final bannerManager = BannerManager();
      await bannerManager.resetAllBannerStates();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ 모든 배너 닫기 기록이 초기화되었습니다.',
              style: TypographyTokens.caption.copyWith(
                color: Colors.white,
              ),
            ),
            backgroundColor: ColorTokens.success,
            behavior: SnackBarBehavior.fixed,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      if (kDebugMode) {
        debugPrint('✅ [Settings] 모든 배너 닫기 기록 초기화 완료');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ 배너 초기화 실패: $e',
              style: TypographyTokens.caption.copyWith(
                color: Colors.white,
              ),
            ),
            backgroundColor: ColorTokens.error,
            behavior: SnackBarBehavior.fixed,
            duration: Duration(seconds: 3),
          ),
        );
      }
      
      if (kDebugMode) {
        debugPrint('❌ [Settings] 배너 초기화 실패: $e');
      }
    }
  }

  // 🔍 구독 상태 간단 진단 (v4-simplified)
  Future<void> _runSubscriptionDebug() async {
    if (!kDebugMode) return;
    
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🔍 구독 상태 확인 중... (콘솔 확인)',
              style: TypographyTokens.caption.copyWith(
                color: Colors.white,
              ),
            ),
            backgroundColor: ColorTokens.primary,
            behavior: SnackBarBehavior.fixed,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      // v4-simplified: 간단한 상태 출력
      final unifiedManager = UnifiedSubscriptionManager();
      final entitlements = await unifiedManager.getSubscriptionEntitlements(forceRefresh: true);
      
      debugPrint('🔍 [Settings] === v4-simplified 구독 상태 ===');
      debugPrint('   권한: ${entitlements['entitlement']}');
      debugPrint('   구독 상태: ${entitlements['subscriptionStatus']}');
      debugPrint('   체험 사용 이력: ${entitlements['hasUsedTrial']}');
      debugPrint('   프리미엄 여부: ${entitlements['isPremium']}');
      debugPrint('   체험 여부: ${entitlements['isTrial']}');
      debugPrint('   상태 메시지: ${entitlements['statusMessage']}');
      debugPrint('   만료 여부: ${entitlements['isExpired']}');
      debugPrint('   활성 여부: ${entitlements['isActive']}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ 구독 상태 확인 완료. 콘솔을 확인하세요.',
              style: TypographyTokens.caption.copyWith(
                color: Colors.white,
              ),
            ),
            backgroundColor: ColorTokens.success,
            behavior: SnackBarBehavior.fixed,
            duration: Duration(seconds: 3),
          ),
        );
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ 구독 상태 확인 실패: $e',
              style: TypographyTokens.caption.copyWith(
                color: Colors.white,
              ),
            ),
            backgroundColor: ColorTokens.error,
            behavior: SnackBarBehavior.fixed,
            duration: Duration(seconds: 3),
          ),
        );
      }
      
      if (kDebugMode) {
        debugPrint('❌ [Settings] 구독 상태 확인 실패: $e');
      }
    }
  }

  void _showUpgradeModal() async {
    // 🚨 이미 업그레이드 모달이 표시 중이면 중복 호출 방지
    if (UpgradeModal.isShowing) {
      if (kDebugMode) {
        debugPrint('⚠️ [Settings] 업그레이드 모달이 이미 표시 중입니다. 중복 호출 방지');
      }
      return;
    }

    try {
      // 🎯 체험 이력에 따른 분기 처리
      final hasUsedFreeTrial = _viewModel.hasUsedFreeTrial;
      final hasEverUsedTrial = _viewModel.hasEverUsedTrial;
      if (hasUsedFreeTrial || hasEverUsedTrial) {
        // 🎯 체험 이력 있음 -> 일반 프리미엄 모달
        UpgradeModal.show(
          context,
          reason: UpgradeReason.general,
          onUpgrade: () {
            debugPrint('🎯 [Settings] 프리미엄 업그레이드 선택 (체험 이력 있음)');
          },
        );
      } else {
        // 🎯 체험 이력 없음 -> 무료체험 유도 모달
        UpgradeModal.show(
          context,
          reason: UpgradeReason.welcomeTrial,
          onUpgrade: () {
            debugPrint('🎯 [Settings] 무료체험 시작 선택');
          },
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Settings] 업그레이드 모달 표시 실패: $e');
      }
      // 오류 시 기본 모달 표시
      UpgradeModal.show(
        context,
        reason: UpgradeReason.settings,
        onUpgrade: () {
          debugPrint('🎯 [Settings] 프리미엄 업그레이드 선택 (기본)');
        },
      );
    }
  }

  /// 🔍 Payment Debug 화면으로 이동
  void _navigateToPaymentDebug() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PaymentDebugScreen(),
      ),
    );
  }
}
