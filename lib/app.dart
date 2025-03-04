import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme/app_theme.dart';
import 'views/screens/home_screen.dart';

class App extends StatefulWidget {
  const App({Key? key}) : super(key: key);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // 현재 사용자가 없으면 익명 로그인 수행
      if (_auth.currentUser == null) {
        print('익명 인증 시작...');
        final userCredential = await _auth.signInAnonymously();
        print('익명 인증 성공: ${userCredential.user?.uid}');
      } else {
        print('기존 사용자 발견: ${_auth.currentUser?.uid}');
      }

      // 인증 후 다시 확인
      if (_auth.currentUser == null) {
        throw Exception('익명 인증 후에도 사용자가 null입니다.');
      }
    } catch (e) {
      print('익명 인증 실패: $e');
      _error = '인증 초기화 중 오류가 발생했습니다: $e';
    } finally {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pikabook',
      theme: AppTheme.lightTheme,
      home: _isInitialized
          ? (_error != null ? _buildErrorScreen() : const HomeScreen())
          : const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error ?? '알 수 없는 오류가 발생했습니다.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _error = null;
                  _isInitialized = false;
                });
                _initializeApp();
              },
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
