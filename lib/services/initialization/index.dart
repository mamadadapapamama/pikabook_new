// 초기화 및 인증 서비스 모듈을 한 번에 내보내는 인덱스 파일
export './initialization_manager.dart';
export './auth_service.dart';

/// 초기화 및 인증 서비스 모듈
/// 
/// 사용 방법:
/// ```dart
/// import 'package:pikabook/services/initialization/index.dart';
/// 
/// // 초기화 및 인증 서비스를 사용할 수 있습니다.
/// final initializationManager = InitializationManager();
/// final authService = AuthService();
/// ```
