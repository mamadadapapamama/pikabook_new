import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../services/initialization_service.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';
import '../../services/user_preferences_service.dart';
import '../../utils/language_constants.dart';
import '../../widgets/dot_loading_indicator.dart';
import 'package:provider/provider.dart';
import '../../widgets/common/pika_button.dart';
import '../../widgets/common/pika_app_bar.dart';

class SettingsScreen extends StatefulWidget {
  final InitializationService initializationService;
  final VoidCallback onLogout;

  const SettingsScreen({
    Key? key,
    required this.initializationService,
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
  
  // 설정 관련 상태 변수
  String _userName = '';
  String _noteSpaceName = '';
  String _sourceLanguage = SourceLanguage.DEFAULT;
  String _targetLanguage = TargetLanguage.DEFAULT;
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserPreferences();
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
      // 사용자 이름 로드
      final userName = await _userPreferences.getUserName();
      
      // 노트 스페이스 정보 로드
      final defaultNoteSpace = await _userPreferences.getDefaultNoteSpace();
      
      // 언어 설정 로드
      final sourceLanguage = await _userPreferences.getSourceLanguage();
      final targetLanguage = await _userPreferences.getTargetLanguage();
      
      if (mounted) {
        setState(() {
          _userName = userName ?? '사용자';
          _noteSpaceName = defaultNoteSpace;
          _sourceLanguage = sourceLanguage;
          _targetLanguage = targetLanguage;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorTokens.background,
      appBar: PikaAppBar.settings(
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      body: _isLoading
          ? const Center(child: DotLoadingIndicator(
              message: '설정 로딩 중...',
              dotColor: ColorTokens.primary,
            ))
          : _buildProfileContent(),
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
          
          // 로그아웃 버튼 (위치 변경: 프로필 바로 아래로)
          _buildLogoutButton(),
          
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
          
          const SizedBox(height: 32),
          
          // 3. 계정 관리 섹션
          _buildSectionTitle('계정관리'),
          const SizedBox(height: 12),
          
          // 회원 탈퇴 버튼 추가
          _buildDeleteAccountButton(),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
  
  // 프로필 카드 위젯
  Widget _buildProfileCard(String displayName, String email, String? photoUrl) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: ColorTokens.surface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // 프로필 이미지
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null
                ? const Icon(Icons.person, size: 24, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 16),
          
          // 사용자 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TypographyTokens.buttonEn,
                ),
                const SizedBox(height: 2),
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
    return Container(
      width: double.infinity,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: ColorTokens.surface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: onTap,
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
    );
  }
  
  // 로그아웃 버튼
  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: PikaButton(
        text: '로그아웃',
        variant: PikaButtonVariant.warning,
        onPressed: () async {
          try {
            // 로그아웃 함수 호출
            widget.onLogout();
            
            // 로그인 화면으로 직접 이동 (백 스택 모두 제거)
            if (mounted && Navigator.canPop(context)) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/',
                (route) => false, // 모든 이전 스택 제거
              );
            }
          } catch (e) {
            debugPrint('로그아웃 오류: $e');
            // 실패 스낵바 표시
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('로그아웃 중 오류가 발생했습니다. 다시 시도해주세요.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        isFullWidth: true,
      ),
    );
  }
  
  // 학습자 이름 설정 다이얼로그
  Future<void> _showUserNameDialog() async {
    final TextEditingController controller = TextEditingController(text: _userName);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
      await _userPreferences.setUserName(result);
      // 사용자 이름이 변경되면 노트 스페이스 이름도 업데이트
      final noteSpaceName = "${result}의 Chinese Notes";
      await _userPreferences.setDefaultNoteSpace(noteSpaceName);
      _loadUserPreferences();
    }
  }
  
  // 노트 스페이스 이름 변경 다이얼로그
  Future<void> _showNoteSpaceNameDialog() async {
    final TextEditingController controller = TextEditingController(text: _noteSpaceName);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
        // 노트 스페이스 이름 변경 (이전 이름과 새 이름 전달)
        final success = await _userPreferences.renameNoteSpace(_noteSpaceName, result);
        
        // 노트 스페이스 이름 저장
        await _userPreferences.setDefaultNoteSpace(result);
        
        // UI 다시 로드
        await _loadUserPreferences();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success 
                  ? '노트 스페이스 이름이 변경되었습니다.' 
                  : '노트 스페이스 이름이 설정되었습니다.',
                style: TypographyTokens.caption.copyWith(
                  color: ColorTokens.textLight,
                ),
              ),
              backgroundColor: ColorTokens.primary,
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
  
  // 원문 언어 설정 다이얼로그
  Future<void> _showSourceLanguageDialog() async {
    final sourceLanguages = [...SourceLanguage.SUPPORTED, ...SourceLanguage.FUTURE_SUPPORTED];
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
      await _userPreferences.setSourceLanguage(result);
      _loadUserPreferences();
    }
  }
  
  // 번역 언어 설정 다이얼로그
  Future<void> _showTargetLanguageDialog() async {
    final targetLanguages = [...TargetLanguage.SUPPORTED, ...TargetLanguage.FUTURE_SUPPORTED];
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
      await _userPreferences.setTargetLanguage(result);
      _loadUserPreferences();
    }
  }
  
  // 회원 탈퇴 버튼
  Widget _buildDeleteAccountButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: PikaButton(
        text: '회원 탈퇴',
        variant: PikaButtonVariant.warning,
        onPressed: _showDeleteAccountConfirmation,
        isFullWidth: true,
      ),
    );
  }
  
  // 회원 탈퇴 확인 다이얼로그
  Future<void> _showDeleteAccountConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
    
    if (confirmed == true) {
      await _deleteAccount();
    }
  }
  
  // 회원 탈퇴 처리
  Future<void> _deleteAccount() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      // 현재 사용자 가져오기
      final user = FirebaseAuth.instance.currentUser;
      
      if (user == null) {
        throw Exception('로그인된 사용자가 없습니다.');
      }
      
      // 사용자 계정 삭제
      await user.delete();
      
      // 로그아웃 처리하고 로그인 화면으로 이동
      widget.onLogout();
      
      // 성공 메시지 표시 후 로그인 화면으로 이동
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('회원 탈퇴가 완료되었습니다.'),
            backgroundColor: ColorTokens.secondary,
          ),
        );
        
        // 로그인 화면으로 이동 (모든 스택 제거)
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/',
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('회원 탈퇴 중 오류 발생: $e');
      
      String errorMessage = '회원 탈퇴 중 오류가 발생했습니다.';
      
      // 재인증 필요 오류 처리
      if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
        errorMessage = '보안을 위해 재로그인이 필요합니다. 로그아웃 후 다시 로그인해주세요.';
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: ColorTokens.error,
          ),
        );
      }
    }
  }
}
