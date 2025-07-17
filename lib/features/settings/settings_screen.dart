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
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

// 뷰모델 및 위젯 임포트
import 'settings_view_model.dart';
import 'widgets/plan_card.dart';
import 'widgets/profile_card.dart';
import 'widgets/setting_item.dart';
import '../../core/widgets/selection_dialog.dart';

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
  // ViewModel은 Provider를 통해 제공되므로 여기서는 생성하지 않음

  @override
  Widget build(BuildContext context) {
    // ChangeNotifierProvider로 ViewModel을 제공
    return ChangeNotifierProvider(
      create: (_) => SettingsViewModel()..initialize(),
      child: Scaffold(
        backgroundColor: ColorTokens.background,
        appBar: PikaAppBar.settings(
          onBackPressed: () => Navigator.of(context).pop(),
        ),
        // Consumer를 사용하여 ViewModel의 변경사항을 UI에 반영
        body: Consumer<SettingsViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.isLoading && !viewModel.isPlanLoaded) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildProfileContent(context, viewModel);
          },
        ),
      ),
    );
  }

  Widget _buildProfileContent(BuildContext context, SettingsViewModel viewModel) {
    final String displayName = viewModel.currentUser?.displayName ?? '사용자';
    final String email = viewModel.currentUser?.email ?? '이메일 없음';
    final String? photoUrl = viewModel.currentUser?.photoURL;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          
          _buildSectionTitle('프로필'),
          const SizedBox(height: 12),
          ProfileCard(
            displayName: displayName,
            email: email,
            photoUrl: photoUrl,
          ),
          
          const SizedBox(height: 16),
          
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
          
          _buildSectionTitle('내 플랜'),
          const SizedBox(height: 12),
          const PlanCard(), // 분리된 PlanCard 위젯 사용
          
          const SizedBox(height: 32),
          
          _buildSectionTitle('노트 설정'),
          const SizedBox(height: 12),
          
          SettingItem(
            title: '학습자 이름',
            value: viewModel.userName,
            onTap: () => _showUserNameDialog(context, viewModel),
          ),
          
          const SizedBox(height: 8),
          
          SettingItem(
            title: '노트스페이스 이름',
            value: viewModel.noteSpaceName,
            onTap: () => _showNoteSpaceNameDialog(context, viewModel),
          ),
          
          const SizedBox(height: 8),

          SettingItem(
            title: '원문 언어',
            value: SourceLanguage.getName(viewModel.sourceLanguage),
            onTap: () => _showSourceLanguageDialog(context, viewModel),
          ),
          
          const SizedBox(height: 8),
          
          SettingItem(
            title: '번역 언어',
            value: TargetLanguage.getName(viewModel.targetLanguage),
            onTap: () => _showTargetLanguageDialog(context, viewModel),
          ),
          
          const SizedBox(height: 8),
          
          SettingItem(
            title: '텍스트 처리 모드',
            value: viewModel.useSegmentMode ? '문장 단위' : '문단 단위',
            onTap: () => _showTextProcessingModeDialog(context, viewModel),
          ),
          
          const SizedBox(height: 32),
          
          _buildSectionTitle('계정관리'),
          const SizedBox(height: 12),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            child: PikaButton(
              text: '회원 탈퇴',
              variant: PikaButtonVariant.warning,
              onPressed: () => _handleAccountDeletion(context, viewModel),
              isFullWidth: true,
            ),
          ),
          
          const SizedBox(height: 32),
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
  
  // 학습자 이름 설정 다이얼로그
  Future<void> _showUserNameDialog(BuildContext context, SettingsViewModel viewModel) async {
    showDialog<void>(
      context: context,
      builder: (context) => EditDialog.forUserName(
        currentName: viewModel.userName,
        onNameUpdated: (newName) async {
          if (newName.isNotEmpty) {
            await viewModel.updateUserName(newName);
          }
        },
      ),
    );
  }
  
  // 노트 스페이스 이름 변경 다이얼로그
  Future<void> _showNoteSpaceNameDialog(BuildContext context, SettingsViewModel viewModel) async {
    showDialog<void>(
      context: context,
      builder: (context) => EditDialog.forNoteSpace(
        currentName: viewModel.noteSpaceName,
        onNameUpdated: (newName) async {
          if (newName.isNotEmpty) {
            final success = await viewModel.updateNoteSpaceName(newName);
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
  Future<void> _showSourceLanguageDialog(BuildContext context, SettingsViewModel viewModel) async {
    final options = [...SourceLanguage.SUPPORTED, ...SourceLanguage.FUTURE_SUPPORTED]
        .map((lang) => SelectionOption(
              value: lang,
              label: SourceLanguage.getName(lang),
              isDisabled: SourceLanguage.FUTURE_SUPPORTED.contains(lang),
              subtitle: SourceLanguage.FUTURE_SUPPORTED.contains(lang) ? '향후 지원 예정' : null,
            ))
        .toList();

    await showDialog<void>(
      context: context,
      builder: (context) => SelectionDialog(
        title: '원문 언어 설정',
        options: options,
        currentValue: viewModel.sourceLanguage,
        onSelected: (value) async {
          await viewModel.updateSourceLanguage(value);
        },
      ),
    );
  }
  
  // 번역 언어 설정 다이얼로그
  Future<void> _showTargetLanguageDialog(BuildContext context, SettingsViewModel viewModel) async {
    final options = [...TargetLanguage.SUPPORTED, ...TargetLanguage.FUTURE_SUPPORTED]
        .map((lang) => SelectionOption(
              value: lang,
              label: TargetLanguage.getName(lang),
              isDisabled: TargetLanguage.FUTURE_SUPPORTED.contains(lang),
              subtitle: TargetLanguage.FUTURE_SUPPORTED.contains(lang) ? '향후 지원 예정' : null,
            ))
        .toList();

    await showDialog<void>(
      context: context,
      builder: (context) => SelectionDialog(
        title: '번역 언어 설정',
        options: options,
        currentValue: viewModel.targetLanguage,
        onSelected: (value) async {
          await viewModel.updateTargetLanguage(value);
        },
      ),
    );
  }
  
  // 텍스트 처리 모드 설정 다이얼로그
  Future<void> _showTextProcessingModeDialog(BuildContext context, SettingsViewModel viewModel) async {
    final options = [
      SelectionOption(
        value: 'true',
        label: '문장 단위',
        subtitle: '문장별로 분리하여 번역하고 발음을 제공합니다.',
      ),
      SelectionOption(
        value: 'false',
        label: '문단 단위',
        subtitle: '문단 단위로 번역해 문맥에 맞는 번역을 제공합니다.',
      ),
    ];

    await showDialog<void>(
      context: context,
      builder: (context) => SelectionDialog(
        title: '텍스트 처리 모드 설정',
        options: options,
        currentValue: viewModel.useSegmentMode.toString(),
        onSelected: (value) async {
          final success = await viewModel.updateTextProcessingMode(value == 'true');
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
        },
      ),
    );
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

  Future<void> _handleAccountDeletion(BuildContext context, SettingsViewModel viewModel) async {
    // 1. 재인증 필요 여부 확인
    final needsReauth = await viewModel.isReauthenticationRequired();
    
    if (needsReauth) {
      // 재인증이 필요한 경우: 재인증 안내 모달
      await _showReauthRequiredDialog(context);
    } else {
      // 재인증이 불필요한 경우: 경고 메시지 후 바로 탈퇴 처리
      await _showWarningAndDelete(context, viewModel);
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
  Future<void> _showWarningAndDelete(BuildContext context, SettingsViewModel viewModel) async {
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
    await _executeAccountDeletion(context, viewModel);
  }
  
  // 실제 탈퇴 처리 실행
  Future<void> _executeAccountDeletion(BuildContext context, SettingsViewModel viewModel) async {
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
      
      final success = await viewModel.deleteAccount();
      
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


  void _showUpgradeModal(BuildContext context, SettingsViewModel viewModel) async {
    // 🚨 이미 업그레이드 모달이 표시 중이면 중복 호출 방지
    if (UpgradeModal.isShowing) {
      if (kDebugMode) {
        debugPrint('⚠️ [Settings] 업그레이드 모달이 이미 표시 중입니다. 중복 호출 방지');
      }
      return;
    }

    try {
      // 🎯 체험 이력에 따른 분기 처리
      final hasUsedFreeTrial = viewModel.hasUsedFreeTrial;
      final hasEverUsedTrial = viewModel.hasEverUsedTrial;
      
      if (kDebugMode) {
        debugPrint('🔍 [Settings] 업그레이드 모달 표시 분기 판단:');
        debugPrint('   hasUsedFreeTrial: $hasUsedFreeTrial');
        debugPrint('   hasEverUsedTrial: $hasEverUsedTrial');
        debugPrint('   플랜 이름: ${viewModel.planName}');
        debugPrint('   플랜 타입: ${viewModel.planType}');
      }
      
      if (hasUsedFreeTrial || hasEverUsedTrial) {
        // 🎯 체험 이력 있음 -> 일반 프리미엄 모달
        if (kDebugMode) {
          debugPrint('🎯 [Settings] 체험 이력 있음 → 일반 프리미엄 모달 표시');
        }
        
        UpgradeModal.show(
          context,
          reason: UpgradeReason.general,
          onUpgrade: () {
            debugPrint('🎯 [Settings] 프리미엄 업그레이드 선택 (체험 이력 있음)');
          },
        );
      } else {
        // 🎯 체험 이력 없음 -> 무료체험 유도 모달
        if (kDebugMode) {
          debugPrint('🎯 [Settings] 체험 이력 없음 → 무료체험 유도 모달 표시');
        }
        
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

  }
