import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../core/services/authentication/user_preferences_service.dart';
import '../../core/utils/language_constants.dart';
import '../../core/widgets/loading_experience.dart';
import '../../../core/widgets/pika_button.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/usage_dialog.dart';
import '../../core/services/authentication/auth_service.dart';
import '../../core/services/common/plan_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _isLoading = false;
  User? _currentUser;
  
  // 사용자 설정 서비스
  final UserPreferencesService _userPreferences = UserPreferencesService();
  // 플랜 서비스 추가
  final PlanService _planService = PlanService();
  
  // 설정 관련 상태 변수
  String _userName = '';
  String _noteSpaceName = '';
  String _sourceLanguage = SourceLanguage.DEFAULT;
  String _targetLanguage = TargetLanguage.DEFAULT;
  bool _useSegmentMode = false;  // 추가: 세그먼트 모드 상태
  
  // 플랜 정보 상태
  String _planType = PlanService.PLAN_FREE;
  String _planName = '무료';
  bool _isBetaPeriod = false;
  int _remainingDays = 0;
  
  // 사용량 정보
  Map<String, int> _planLimits = {};
  Map<String, dynamic> _currentUsage = {};
  Map<String, double> _usagePercentages = {};
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserPreferences();
    _loadPlanInfo();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _currentUser = FirebaseAuth.instance.currentUser;
    } catch (e) {
      debugPrint('사용자 정보 로드 오류: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // 사용자 설정 로드
  Future<void> _loadUserPreferences() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final preferences = await _userPreferences.getPreferences();
      
      if (mounted) {
        setState(() {
          _userName = preferences.userName ?? '사용자';
          _noteSpaceName = preferences.defaultNoteSpace;
          _sourceLanguage = preferences.sourceLanguage;
          _targetLanguage = preferences.targetLanguage;
          _useSegmentMode = preferences.useSegmentMode;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('사용자 설정 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 사용자 플랜 정보 로드
  Future<void> _loadPlanInfo() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      if (kDebugMode) {
        print('🔍 PlanService 테스트 시작');
        
        // 1. 현재 플랜 타입 확인
        final currentPlanType = await _planService.getCurrentPlanType();
        print('   현재 플랜 타입: $currentPlanType');
        
        // 2. 플랜 이름 확인
        final planName = _planService.getPlanName(currentPlanType);
        print('   플랜 이름: $planName');
        
        // 3. 플랜 제한 확인
        final planLimits = await _planService.getPlanLimits(currentPlanType);
        print('   플랜 제한: $planLimits');
        
        // 4. 현재 사용량 확인
        final currentUsage = await _planService.getCurrentUsage();
        print('   현재 사용량: $currentUsage');
        
        // 5. 사용량 퍼센트 확인
        final usagePercentages = await _planService.getUsagePercentages();
        print('   사용량 퍼센트: $usagePercentages');
      }
      
      final planDetails = await _planService.getPlanDetails();
      
      if (mounted) {
        setState(() {
          _planType = planDetails['planType'] as String;
          _planName = planDetails['planName'] as String;
          _planLimits = Map<String, int>.from(planDetails['planLimits'] as Map);
          _currentUsage = planDetails['currentUsage'] as Map<String, dynamic>;
          _usagePercentages = Map<String, double>.from(planDetails['usagePercentages'] as Map);
          _isBetaPeriod = planDetails['isBetaPeriod'] as bool? ?? false;
          _remainingDays = planDetails['remainingDays'] as int? ?? 0;
          _isLoading = false;
        });
        
        if (kDebugMode) {
          print('✅ PlanService 테스트 완료');
          print('   UI 상태 업데이트: 플랜=$_planName, 제한=$_planLimits');
        }
      }
    } catch (e) {
      debugPrint('❌ 플랜 정보 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
          if (!_isLoading) {
            await _loadUserData();
            await _loadUserPreferences();
            await _loadPlanInfo();
          }
        },
        contentBuilder: (context) => _buildProfileContent(),
      ),
    );
  }

  Widget _buildProfileContent() {
    // 익명 사용자 체크 제거 (더 이상 익명 로그인 사용하지 않음)
    final String displayName = _currentUser?.displayName ?? '사용자';
    final String email = _currentUser?.email ?? '이메일 없음';
    final String? photoUrl = _currentUser?.photoURL;

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
          
          // 로그아웃 버튼 - 전체 너비 버튼으로 변경
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
          
          // 현재 사용 중인 플랜 정보 섹션 추가
          _buildSectionTitle('내 플랜'),
          const SizedBox(height: 12),
          _buildPlanInfoCard(),
          
          const SizedBox(height: 32),
          
          // 2. 노트 설정 섹션
          _buildSectionTitle('노트 설정'),
          const SizedBox(height: 12),
          
          // 학습자 이름 설정
          _buildSettingItem(
            title: '학습자 이름',
            value: _userName,
            onTap: _showUserNameDialog,
          ),
          
          const SizedBox(height: 8),
          
          // 노트 스페이스 이름 설정
          _buildSettingItem(
            title: '노트스페이스 이름',
            value: _noteSpaceName,
            onTap: _showNoteSpaceNameDialog,
          ),
          
          const SizedBox(height: 8),
          
          // 원문 언어 설정
          _buildSettingItem(
            title: '원문 언어',
            value: SourceLanguage.getName(_sourceLanguage),
            onTap: _showSourceLanguageDialog,
          ),
          
          const SizedBox(height: 8),
          
          // 번역 언어 설정
          _buildSettingItem(
            title: '번역 언어',
            value: TargetLanguage.getName(_targetLanguage),
            onTap: _showTargetLanguageDialog,
          ),
          
          const SizedBox(height: 8),
          
          // 텍스트 처리 모드 설정 추가
          _buildSettingItem(
            title: '텍스트 처리 모드',
            value: _useSegmentMode ? '문장 단위' : '문단 단위',
            onTap: _showTextProcessingModeDialog,
          ),
          
          const SizedBox(height: 32),
          
          // 3. 계정 관리 섹션
          _buildSectionTitle('계정관리'),
          const SizedBox(height: 12),
          
          // 회원 탈퇴 버튼 (빨간색 텍스트)
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
                SizedBox(height: SpacingTokens.xs/2),
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
  
  // 학습자 이름 설정 다이얼로그
  Future<void> _showUserNameDialog() async {
    final TextEditingController controller = TextEditingController(text: _userName);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: Text('학습자 이름 설정', style: TypographyTokens.subtitle2),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: '이름',
            hintText: '학습자 이름을 입력하세요',
            labelStyle: TypographyTokens.caption.copyWith(
              color: ColorTokens.textSecondary,
            ),
            hintStyle: TypographyTokens.caption.copyWith(
              color: ColorTokens.textTertiary,
            ),
            border: const OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: ColorTokens.primary, width: 2),
              borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
            ),
          ),
          autofocus: true,
          style: TypographyTokens.body1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '취소',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.textTertiary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(
              '저장',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.primary,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty) {
      final preferences = await _userPreferences.getPreferences();
      await _userPreferences.savePreferences(
        preferences.copyWith(
          userName: result,
          defaultNoteSpace: "${result}의 학습 노트"
        )
      );
      _loadUserPreferences();
    }
  }
  
  // 노트 스페이스 이름 변경 다이얼로그
  Future<void> _showNoteSpaceNameDialog() async {
    final TextEditingController controller = TextEditingController(text: _noteSpaceName);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: Text('노트 스페이스 이름 변경', style: TypographyTokens.subtitle2),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: '이름',
            hintText: '노트 스페이스 이름을 입력하세요',
            labelStyle: TypographyTokens.caption.copyWith(
              color: ColorTokens.textSecondary,
            ),
            hintStyle: TypographyTokens.caption.copyWith(
              color: ColorTokens.textTertiary,
            ),
            border: const OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: ColorTokens.primary, width: 2),
            ),
          ),
          autofocus: true,
          style: TypographyTokens.body1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '취소',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.textTertiary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(
              '저장',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.primary,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty) {
      try {
        final preferences = await _userPreferences.getPreferences();
        final noteSpaces = List<String>.from(preferences.noteSpaces);
        
        // 노트 스페이스 이름 변경
        if (noteSpaces.contains(_noteSpaceName)) {
          final index = noteSpaces.indexOf(_noteSpaceName);
          noteSpaces[index] = result;
        } else if (!noteSpaces.contains(result)) {
          noteSpaces.add(result);
        }
        
        await _userPreferences.savePreferences(
          preferences.copyWith(
            defaultNoteSpace: result,
            noteSpaces: noteSpaces
          )
        );
        
        // UI 다시 로드
        await _loadUserPreferences();
        
        // 전역 상태를 통해 변경 사실을 알림
        await _notifyNoteSpaceNameChanged(result);
        
        if (mounted) {
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
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '노트 스페이스 이름 변경 중 오류가 발생했습니다: $e',
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
  }
  
  // 노트스페이스 이름 변경 알림 메서드
  Future<void> _notifyNoteSpaceNameChanged(String newName) async {
    // 1. SharedPreferences에 마지막 변경 시간 기록 (타임스탬프)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_notespace_change', DateTime.now().millisecondsSinceEpoch);
    
    // 2. 앱 내 다른 화면을 강제로 갱신하기 위한 특수 플래그 설정
    await prefs.setString('last_changed_notespace_name', newName);
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
                          color: ColorTokens.textTertiary,
                        ),
                      )
                    : null,
                value: language,
                groupValue: _sourceLanguage,
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
                color: ColorTokens.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (result != null) {
      final preferences = await _userPreferences.getPreferences();
      await _userPreferences.savePreferences(
        preferences.copyWith(sourceLanguage: result)
      );
      _loadUserPreferences();
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
                          color: ColorTokens.textTertiary,
                        ),
                      )
                    : null,
                value: language,
                groupValue: _targetLanguage,
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
                color: ColorTokens.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (result != null) {
      final preferences = await _userPreferences.getPreferences();
      await _userPreferences.savePreferences(
        preferences.copyWith(targetLanguage: result)
      );
      _loadUserPreferences();
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
                  color: ColorTokens.textTertiary,
                ),
              ),
              value: true,
              groupValue: _useSegmentMode,
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
                  color: ColorTokens.textTertiary,
                ),
              ),
              value: false,
              groupValue: _useSegmentMode,
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
                color: ColorTokens.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (result != null) {
      final preferences = await _userPreferences.getPreferences();
      await _userPreferences.savePreferences(
        preferences.copyWith(useSegmentMode: result)
      );
      _loadUserPreferences();
      
      // 설정 변경 알림
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '텍스트 처리 모드가 변경되었습니다. 새로 열리는 노트에 적용됩니다.',
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
  Future<void> _handleAccountDeletion(BuildContext context) async {
    // 확인 다이얼로그 표시
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
              '회원 탈퇴',
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
    
    // 로딩 표시
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 회원 탈퇴 처리
      await _deleteAccount();
      
      // 로딩 종료
      setState(() {
        _isLoading = false;
      });
      
      // 성공 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('계정이 성공적으로 삭제되었습니다.')),
        );
        
        // 로그인 화면으로 이동
        Navigator.pushNamedAndRemoveUntil(
          context, 
          '/', 
          (route) => false
        );
        
        // 로그아웃 콜백 호출 (UI 상태 변경)
        widget.onLogout();
      }
    } catch (e) {
      // 오류 처리
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('계정 삭제 중 오류가 발생했습니다: $e'),
          ),
        );
      }
    }
  }

  // 회원 탈퇴 처리
  Future<void> _deleteAccount() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 현재 사용자 가져오기
      final user = FirebaseAuth.instance.currentUser;
      
      if (user == null) {
        throw '로그인된 사용자 정보를 찾을 수 없습니다.';
      }
      
      // AuthService의 deleteAccount 메서드 사용
      // Firebase Auth 계정 삭제 + Firestore 데이터 삭제 + 로컬 데이터 삭제 모두 포함
      final authService = AuthService();
      await authService.deleteAccount();
      
      // 로딩 종료
      setState(() {
        _isLoading = false;
      });
      
      // 로그아웃 콜백 호출
      widget.onLogout();
      
    } catch (e) {
      debugPrint('계정 삭제 오류: $e');
      
      // 오류가 발생해도 사용자에게는 성공적으로 처리된 것처럼 보여줌
      setState(() {
        _isLoading = false;
      });
      
      // 로그아웃 콜백 호출 - 오류가 발생해도 로그아웃 처리
      widget.onLogout();
    }
  }

  // 플랜 정보 카드 위젯
  Widget _buildPlanInfoCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 플랜 이름
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _planName,
                style: TypographyTokens.body2.copyWith(
                  color: ColorTokens.textPrimary,
                ),
              ),
            ],
          ),
          
          // 사용량 확인 버튼
          GestureDetector(
            onTap: _showUsageDialog,
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
        ],
      ),
    );
  }
  
  // 사용량 프로그레스 바 위젯
  Widget _buildUsageSummary() {
    final usageItems = [
      {
        'key': 'ocrPages',
        'label': 'OCR',
        'current': '${_currentUsage['ocrPages'] ?? 0}',
        'limit': _planLimits['ocrPages'] ?? 1,
        'percentage': _usagePercentages['ocr'] ?? 0.0,
      },
      {
        'key': 'storageBytes',
        'label': '저장 공간',
        'current': _formatBytes(_currentUsage['storageUsageBytes'] ?? 0),
        'limit': _formatBytes(_planLimits['storageBytes'] ?? 1),
        'percentage': _usagePercentages['storage'] ?? 0.0,
      },
    ];
    
    return Column(
      children: usageItems.map((item) {
        final double percentage = (item['percentage'] as double).clamp(0, 100);
        final bool isWarning = percentage > 80;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item['label'] as String,
                    style: TypographyTokens.caption.copyWith(
                      color: ColorTokens.textSecondary,
                    ),
                  ),
                  Text(
                    '${item['current']} / ${item['limit']}',
                    style: TypographyTokens.caption.copyWith(
                      color: isWarning ? ColorTokens.error : ColorTokens.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: percentage / 100,
                backgroundColor: ColorTokens.divider,
                valueColor: AlwaysStoppedAnimation<Color>(
                  percentage > 90
                      ? ColorTokens.error
                      : percentage > 70
                          ? Colors.orange
                          : ColorTokens.primary,
                ),
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
  
  // 사용량 다이얼로그 표시
  Future<void> _showUsageDialog() async {
    // 다이얼로그를 즉시 표시하고 내부에서 데이터 로드
    if (context.mounted) {
      await UsageDialog.show(
        context,
        // 현재 캐시된 데이터를 먼저 전달 (빠른 초기 표시용)
        limitStatus: null,  // null로 설정하여 다이얼로그 내부에서 새로 로드하도록 함
        usagePercentages: _usagePercentages,  // 현재 있는 데이터 전달
        onContactSupport: _contactSupport,
      );
    }
  }
  
  // 문의하기 기능
  void _contactSupport() async {
    try {
      // 현재 사용량 및 플랜 정보를 포함한 문의 내용 생성
      final planName = _planName;
      final ocrUsage = _currentUsage['ocrPages'] ?? 0;
      final storageUsage = _formatBytes(_currentUsage['storageUsageBytes'] ?? 0);
      
      final subject = '[피카북] 사용량 문의';
      final body = '플랜: $planName\n'
                 'OCR 사용량: $ocrUsage\n'
                 '저장 공간: $storageUsage\n'
                 '사용자 ID: ${_currentUser?.uid ?? '알 수 없음'}\n';
      
      // PlanService의 문의하기 기능 호출
      await _planService.contactSupport(subject: subject, body: body);
      
      // 성공 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('문의가 등록되었습니다.'),
            backgroundColor: ColorTokens.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('문의 등록 중 오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
          ),
        );
      }
    }
  }
  
  // 바이트 크기 포맷팅
  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  // 사용량 정보 로드
  Future<void> _loadUsageLimits() async {
    try {
      // 현재 플랜 타입 가져오기
      final planType = await _planService.getCurrentPlanType();
      
      // 플랜 서비스를 통해 현재 사용량 및 제한 가져오기
      final planLimits = await _planService.getPlanLimits(planType);
      final currentUsage = await _planService.getCurrentUsage();
      final usagePercentages = await _planService.getUsagePercentages();
      
      if (mounted) {
        setState(() {
          _planLimits = planLimits;
          _currentUsage = currentUsage;
          _usagePercentages = usagePercentages;
        });
      }
    } catch (e) {
      debugPrint('사용량 정보 로드 중 오류: $e');
    }
  }
}
