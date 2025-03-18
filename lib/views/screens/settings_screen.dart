import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/initialization_service.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../services/user_preferences_service.dart';
import '../../utils/language_constants.dart';
import 'package:firebase_core/firebase_core.dart';

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
  NoteViewMode _defaultNoteViewMode = NoteViewMode.segmentMode;
  
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
      
      // 노트 뷰 모드 로드
      final noteViewMode = await _userPreferences.getDefaultNoteViewMode();
      
      if (mounted) {
        setState(() {
          _userName = userName ?? '사용자';
          _noteSpaceName = defaultNoteSpace;
          _sourceLanguage = sourceLanguage;
          _targetLanguage = targetLanguage;
          _defaultNoteViewMode = noteViewMode;
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
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: ColorTokens.primary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildProfileContent(),
    );
  }

  Widget _buildProfileContent() {
    final bool isAnonymous = _currentUser?.isAnonymous ?? true;
    final String displayName = _currentUser?.displayName ?? '익명 사용자';
    final String email = _currentUser?.email ?? '이메일 없음';
    final String? photoUrl = _currentUser?.photoURL;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 프로필 정보 섹션
          _buildSectionTitle('프로필 정보'),
          Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
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
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isAnonymous ? Colors.amber.shade100 : Colors.green.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 2. 설정 섹션
          _buildSectionTitle('설정'),
          
          // 학습자 이름 설정
          _buildSettingItem(
            icon: Icons.person,
            title: '학습자 이름',
            subtitle: _userName,
            onTap: _showUserNameDialog,
          ),
          
          // 노트 스페이스 이름 설정
          _buildSettingItem(
            icon: Icons.edit,
            title: '노트 스페이스 이름',
            subtitle: _noteSpaceName,
            onTap: _showNoteSpaceNameDialog,
          ),
          
          // 원문 언어 설정
          _buildSettingItem(
            icon: Icons.language,
            title: '원문 언어',
            subtitle: SourceLanguage.getName(_sourceLanguage),
            onTap: _showSourceLanguageDialog,
          ),
          
          // 번역 언어 설정
          _buildSettingItem(
            icon: Icons.translate,
            title: '번역 언어',
            subtitle: TargetLanguage.getName(_targetLanguage),
            onTap: _showTargetLanguageDialog,
          ),
          
          // 기본 노트 뷰 설정
          _buildSettingItem(
            icon: Icons.visibility,
            title: '기본 노트 뷰 (모든 노트에 적용)',
            subtitle: _defaultNoteViewMode == NoteViewMode.segmentMode 
                ? '문장별 학습 뷰(세그먼트 모드)' 
                : '원문 전체 번역 뷰(전체 텍스트 모드)',
            onTap: _showNoteViewModeDialog,
          ),
          
          const SizedBox(height: 24),
          
          // 3. 계정 관리 섹션
          _buildSectionTitle('계정 관리'),
          
          // 로그아웃 버튼
          _buildSettingItem(
            icon: Icons.logout,
            title: '로그아웃',
            subtitle: '계정에서 로그아웃합니다',
            color: Colors.red,
            onTap: _handleLogout,
          ),

          // 익명 계정인 경우 소셜 계정 연결 옵션 표시
          if (isAnonymous) ...[
            const SizedBox(height: 16),
            _buildSectionTitle('계정 연결'),
            
            _buildSettingItem(
              icon: Icons.g_mobiledata,
              title: 'Google 계정 연결',
              subtitle: '익명 계정을 Google 계정으로 업그레이드합니다',
              color: Colors.blue,
              onTap: _linkWithGoogle,
            ),
            
            _buildSettingItem(
              icon: Icons.apple,
              title: 'Apple 계정 연결',
              subtitle: '익명 계정을 Apple 계정으로 업그레이드합니다',
              color: Colors.black,
              onTap: _linkWithApple,
            ),
          ],
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
  
  // 섹션 제목 위젯
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: ColorTokens.primary,
        ),
      ),
    );
  }
  
  // 설정 항목 위젯
  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color ?? ColorTokens.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
  
  // 학습자 이름 설정 다이얼로그
  Future<void> _showUserNameDialog() async {
    final TextEditingController controller = TextEditingController(text: _userName);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('학습자 이름 설정'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '이름',
            hintText: '학습자 이름을 입력하세요',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('저장'),
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
        title: const Text('노트 스페이스 이름 변경'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '이름',
            hintText: '노트 스페이스 이름을 입력하세요',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty) {
      await _userPreferences.setDefaultNoteSpace(result);
      _loadUserPreferences();
    }
  }
  
  // 원문 언어 설정 다이얼로그
  Future<void> _showSourceLanguageDialog() async {
    final sourceLanguages = [...SourceLanguage.SUPPORTED, ...SourceLanguage.FUTURE_SUPPORTED];
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('원문 언어 설정'),
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
                title: Text(SourceLanguage.getName(language)),
                subtitle: isFutureSupported 
                    ? const Text('향후 지원 예정', style: TextStyle(color: Colors.grey))
                    : null,
                value: language,
                groupValue: _sourceLanguage,
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
            child: const Text('취소'),
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
        title: const Text('번역 언어 설정'),
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
                title: Text(TargetLanguage.getName(language)),
                subtitle: isFutureSupported 
                    ? const Text('향후 지원 예정', style: TextStyle(color: Colors.grey))
                    : null,
                value: language,
                groupValue: _targetLanguage,
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
            child: const Text('취소'),
          ),
        ],
      ),
    );
    
    if (result != null) {
      await _userPreferences.setTargetLanguage(result);
      _loadUserPreferences();
    }
  }
  
  // 기본 노트 뷰 모드 설정 다이얼로그
  Future<void> _showNoteViewModeDialog() async {
    final result = await showDialog<NoteViewMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기본 노트 뷰 모드 설정'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '모든 노트에 적용할 기본 보기 모드를 선택하세요.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              RadioListTile<NoteViewMode>(
                title: const Text('문장별 학습 뷰'),
                subtitle: const Text('문장 단위로 끊어서 학습하기 좋은 형태'),
                value: NoteViewMode.segmentMode,
                groupValue: _defaultNoteViewMode,
                onChanged: (value) {
                  Navigator.pop(context, value);
                },
              ),
              RadioListTile<NoteViewMode>(
                title: const Text('원문 전체 번역 뷰'),
                subtitle: const Text('원문과 번역을 전체적으로 확인하기 좋은 형태'),
                value: NoteViewMode.fullTextMode,
                groupValue: _defaultNoteViewMode,
                onChanged: (value) {
                  Navigator.pop(context, value);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
    
    if (result != null) {
      await _userPreferences.setDefaultNoteViewMode(result);
      _loadUserPreferences();
    }
  }
  
  // 로그아웃 처리
  Future<void> _handleLogout() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      await FirebaseAuth.instance.signOut();
      widget.onLogout();
    } catch (e) {
      debugPrint('로그아웃 오류: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그아웃 중 오류가 발생했습니다: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // Google 계정 연결
  Future<void> _linkWithGoogle() async {
    // 구현 예정
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google 계정 연결 기능은 아직 구현되지 않았습니다.')),
    );
  }
  
  // Apple 계정 연결
  Future<void> _linkWithApple() async {
    // 구현 예정
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Apple 계정 연결 기능은 아직 구현되지 않았습니다.')),
    );
  }
}

/// 노트 보기 모드 정의
enum NoteViewMode {
  segmentMode,    // 세그먼트 모드 (문장별 번역)
  fullTextMode,   // 전체 텍스트 모드 (전체 번역)
}
