import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/services/authentication/auth_service.dart';

enum SocialLoginType { google, apple }
enum AuthState { idle, loading, error, success }

class LoginViewModel extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isDisposed = false; // 🎯 추가
  AuthState _state = AuthState.idle;
  String? _errorMessage;
  bool _isSignUp = false;
  bool _isEmailLogin = false;

  AuthState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isSignUp => _isSignUp;
  bool get isEmailLogin => _isEmailLogin;
  bool get isLoading => _state == AuthState.loading;
  
  @override
  void dispose() {
    _isDisposed = true; // 🎯 추가
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _setState(AuthState newState) {
    if (_isDisposed) return; // 🎯 추가
    _state = newState;
    notifyListeners();
  }

  void _setError(String? message) {
    if (_isDisposed) return; // 🎯 추가
    _errorMessage = message;
    _state = (message != null) ? AuthState.error : AuthState.idle;
    notifyListeners();
  }

  void toggleEmailLogin(bool value) {
    _isEmailLogin = value;
    _errorMessage = null;
    notifyListeners();
  }

  void toggleSignUp() {
    _isSignUp = !_isSignUp;
    _errorMessage = null;
    notifyListeners();
  }

  Future<User?> handleEmailAuth() async {
    if (isLoading) return null;
    _setState(AuthState.loading);
    _setError(null);

    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();
      User? user;

      if (_isSignUp) {
        user = await _authService.signUpWithEmail(email, password);
      } else {
        user = await _authService.signInWithEmail(email, password);
      }
      
      if (_isDisposed) return null; // 🎯 추가

      _setState(AuthState.success);
      return user;
    } on FirebaseAuthException catch (e) {
      if (_isDisposed) return null; // 🎯 추가
      _setError(_mapAuthException(e));
      return null;
    } catch (e) {
      if (_isDisposed) return null; // 🎯 추가
      _setError('알 수 없는 오류가 발생했습니다.');
      return null;
    }
  }

  Future<User?> handleSocialSignIn(SocialLoginType type) async {
    if (isLoading) return null;
    _setState(AuthState.loading);
    _setError(null);

    try {
      User? user;
      switch (type) {
        case SocialLoginType.google:
          user = await _authService.signInWithGoogle();
          break;
        case SocialLoginType.apple:
          user = await _authService.signInWithApple();
          break;
      }
      
      if (_isDisposed) return null; // 🎯 추가

      _setState(AuthState.success);
      return user;
    } catch (e) {
      if (_isDisposed) return null; // 🎯 추가
      _setError('소셜 로그인 중 오류가 발생했습니다.');
      return null;
    }
  }

  Future<void> sendPasswordResetEmail() async {
    if (isLoading) return;
    _setState(AuthState.loading);
    try {
      await _authService.sendPasswordResetEmail(emailController.text.trim());
      if (_isDisposed) return;
      _setState(AuthState.idle);
    } catch (e) {
      if (_isDisposed) return;
      _setError(e is FirebaseAuthException ? _mapAuthException(e) : '메일 발송에 실패했습니다.');
      rethrow;
    }
  }

  Future<void> resendVerificationEmail() async {
    await _authService.resendEmailVerification();
  }

  String _mapAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return '유효하지 않은 이메일 형식입니다.';
      case 'user-disabled':
        return '비활성화된 계정입니다.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return '이메일 또는 비밀번호가 올바르지 않습니다.';
      case 'email-already-in-use':
        return '이미 사용 중인 이메일입니다.';
      case 'weak-password':
        return '비밀번호는 6자리 이상이어야 합니다.';
      case 'network-request-failed':
        return '네트워크 연결을 확인해주세요.';
      default:
        debugPrint('Firebase Auth 오류: ${e.code}');
        return '인증 중 오류가 발생했습니다. (${e.code})';
    }
  }
} 