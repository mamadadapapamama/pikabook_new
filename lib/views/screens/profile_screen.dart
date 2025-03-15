import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/initialization_service.dart';
import '../../theme/tokens/color_tokens.dart';
import 'package:firebase_core/firebase_core.dart';

class ProfileScreen extends StatefulWidget {
  final InitializationService initializationService;
  final VoidCallback onLogout;

  const ProfileScreen({
    Key? key,
    required this.initializationService,
    required this.onLogout,
  }) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = false;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserData();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 프로필'),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 프로필 이미지
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null
                ? const Icon(Icons.person, size: 50, color: Colors.grey)
                : null,
          ),
          const SizedBox(height: 16),

          // 사용자 이름
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // 이메일
          Text(
            email,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),

          // 계정 유형
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:
                  isAnonymous ? Colors.amber.shade100 : Colors.green.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              isAnonymous ? '익명 계정' : '소셜 계정',
              style: TextStyle(
                color:
                    isAnonymous ? Colors.amber.shade900 : Colors.green.shade900,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 32),

          // 계정 관리 섹션
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            '계정 관리',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // 로그아웃 버튼
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('로그아웃'),
            subtitle: const Text('계정에서 로그아웃합니다'),
            onTap: _handleLogout,
            tileColor: Colors.red.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 16),

          // 익명 계정인 경우 소셜 계정 연결 옵션 표시
          if (isAnonymous) ...[
            const Text(
              '계정 연결',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.g_mobiledata, color: Colors.blue),
              title: const Text('Google 계정 연결'),
              subtitle: const Text('익명 계정을 Google 계정으로 업그레이드합니다'),
              onTap: _linkWithGoogle,
              tileColor: Colors.blue.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.apple, color: Colors.black),
              title: const Text('Apple 계정 연결'),
              subtitle: const Text('익명 계정을 Apple 계정으로 업그레이드합니다'),
              onTap: _linkWithApple,
              tileColor: Colors.grey.shade200,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('정말 로그아웃하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              setState(() {
                _isLoading = true;
              });

              try {
                await widget.initializationService.signOut();
                widget.onLogout();
              } catch (e) {
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
            },
            child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _linkWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Firebase 초기화 확인
      if (!Firebase.apps.isNotEmpty) {
        throw Exception('Firebase가 초기화되지 않았습니다.');
      }

      // 익명 계정을 Google 계정과 연결
      await widget.initializationService.linkAnonymousAccountWithGoogle();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google 계정 연결에 성공했습니다')),
      );
      _loadUserData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google 계정 연결 중 오류가 발생했습니다: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _linkWithApple() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Firebase 초기화 확인
      if (!Firebase.apps.isNotEmpty) {
        throw Exception('Firebase가 초기화되지 않았습니다.');
      }

      // 익명 계정을 Apple 계정과 연결
      await widget.initializationService.linkAnonymousAccountWithApple();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apple 계정 연결에 성공했습니다')),
      );
      _loadUserData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Apple 계정 연결 중 오류가 발생했습니다: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
