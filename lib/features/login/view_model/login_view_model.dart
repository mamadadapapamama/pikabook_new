import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/authentication/auth_service.dart';

enum LoginState { idle, loading, success, error }
enum SocialLoginType { google, apple }

class LoginViewModel with ChangeNotifier {
  final AuthService _authService = AuthService();

  // State
  LoginState _state = LoginState.idle;
  String? _errorMessage;
  bool _isEmailLogin = false;
  bool _isSignUp = false;

  // Controllers
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // Getters
  LoginState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isEmailLogin => _isEmailLogin;
  bool get isSignUp => _isSignUp;
  bool get isLoading => _state == LoginState.loading;

  // Constructor
  LoginViewModel() {
    // Clean up controllers
    emailController.addListener(() {
      if (_errorMessage != null) {
        _clearError();
      }
    });
    passwordController.addListener(() {
      if (_errorMessage != null) {
        _clearError();
      }
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // --- State Management ---

  void _setState(LoginState newState) {
    _state = newState;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _setState(LoginState.error);
  }

  void _clearError() {
    _errorMessage = null;
    if (_state == LoginState.error) {
      _setState(LoginState.idle);
    }
  }
  
  void _setLoading() {
      _errorMessage = null;
      _setState(LoginState.loading);
  }


  // --- UI Interactions ---

  void toggleEmailLogin(bool show) {
    _isEmailLogin = show;
    _isSignUp = false; // Reset sign up state when switching
    _clearError();
    emailController.clear();
    passwordController.clear();
    notifyListeners();
  }

  void toggleSignUp() {
    _isSignUp = !_isSignUp;
    _clearError();
    notifyListeners();
  }

  // --- Authentication Logic ---

  Future<User?> handleSocialSignIn(SocialLoginType type) async {
    _setLoading();
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

      if (user != null) {
        _setState(LoginState.success);
        return user;
      } else {
        // User cancelled the sign in
        _setState(LoginState.idle);
        return null;
      }
    } on FirebaseAuthException catch (e) {
      _setError(_mapAuthException(e.code));
    } catch (e) {
      _setError('로그인 중 오류가 발생했습니다. 다시 시도해 주세요.');
    }
    return null;
  }
  
  Future<User?> handleEmailAuth() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    // Validation
    if (email.isEmpty || password.isEmpty) {
        _setError('이메일과 비밀번호를 입력해주세요.');
        return null;
    }
    if (!email.contains('@') || !email.contains('.')) {
        _setError('올바른 이메일 형식을 입력해주세요.');
        return null;
    }
    if (password.length < 6) {
        _setError('비밀번호는 6자 이상이어야 합니다.');
        return null;
    }

    _setLoading();
    try {
      User? user;
      if (_isSignUp) {
        user = await _authService.signUpWithEmail(email, password);
      } else {
        user = await _authService.signInWithEmail(email, password);
      }
      
      if (user != null) {
          _setState(LoginState.success);
      } else {
          _setError('로그인에 실패했습니다. 다시 시도해주세요.');
      }
      return user;

    } on FirebaseAuthException catch (e) {
        final errorMessage = _mapAuthException(e.code);
        _setError(errorMessage);
        
        // Auto-switch between login/signup forms on specific errors
        if (e.code == 'user-not-found' && !_isSignUp) {
            Future.delayed(Duration(milliseconds: 100), () => toggleSignUp());
        } else if (e.code == 'email-already-in-use' && _isSignUp) {
            Future.delayed(Duration(milliseconds: 100), () => toggleSignUp());
        }
    } catch (e) {
      _setError('오류가 발생했습니다. 다시 시도해주세요.');
    }
    return null;
  }

  Future<void> sendPasswordResetEmail() async {
      final email = emailController.text.trim();
      if (email.isEmpty || !email.contains('@')) {
          throw Exception('올바른 이메일을 입력해주세요.');
      }
      _setLoading();
      try {
          await _authService.sendPasswordResetEmail(email);
          _setState(LoginState.idle);
      } catch (e) {
          _setState(LoginState.idle);
          if (e is FirebaseAuthException) {
            throw Exception(_mapAuthException(e.code));
          }
          throw Exception('메일 발송에 실패했습니다. 잠시 후 다시 시도해주세요.');
      }
  }
  
  Future<void> resendVerificationEmail() async {
      await _authService.resendEmailVerification();
  }


  String _mapAuthException(String code) {
    switch (code) {
      case 'user-not-found':
        return '등록되지 않은 이메일입니다. 회원가입을 먼저 해주세요.';
      case 'wrong-password':
        return '비밀번호가 올바르지 않습니다. 비밀번호를 확인해주세요.';
      case 'email-already-in-use':
        return '이미 가입된 이메일입니다. 로그인해주세요.';
      case 'weak-password':
        return '비밀번호가 너무 약합니다. 6자 이상, 숫자와 문자를 포함해주세요.';
      case 'invalid-email':
        return '올바르지 않은 이메일 형식입니다. 다시 확인해주세요.';
      case 'too-many-requests':
        return '너무 많은 시도가 있었습니다. 5분 후 다시 시도해주세요.';
      case 'network-request-failed':
        return '네트워크 연결에 실패했습니다. 인터넷 연결을 확인해주세요.';
      case 'cancelled':
      case 'sign_in_cancelled':
      case 'AuthorizationError Code=1001':
        return '로그인이 취소되었습니다.';
      default:
        return '알 수 없는 오류가 발생했습니다: $code';
    }
  }
} 