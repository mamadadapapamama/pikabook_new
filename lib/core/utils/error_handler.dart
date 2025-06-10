import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// 에러 유형 열거형
enum ErrorType {
  network,           // 인터넷 연결 문제
  serverConnection,  // 서버 연결 불안정
  timeout,          // 타임아웃
  general,          // 일반적인 에러
  notFound,         // 찾을 수 없음 (404)
  unauthorized,     // 인증 실패 (401)
  forbidden,        // 권한 없음 (403)
  rateLimited,      // 요청 제한 (429)
  storage,          // 저장공간 부족
  permission,       // 권한 문제
}

/// 기능별 에러 컨텍스트
enum ErrorContext {
  dictionary,       // 사전 검색
  flashcard,        // 플래시카드
  noteCreation,     // 노트 생성
  noteEdit,         // 노트 편집
  noteDelete,       // 노트 삭제
  ocr,             // OCR 처리
  llm,             // LLM 번역
  tts,             // 음성 합성
  upload,          // 파일 업로드
  general,         // 일반적인 기능
}

/// 에러 처리 유틸리티 클래스
class ErrorHandler {
  /// 에러 객체나 메시지를 분석하여 적절한 에러 유형 반환
  static ErrorType analyzeError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (kDebugMode) {
      debugPrint('🔍 [ErrorHandler] 에러 분석: $errorString');
    }
    
    // 네트워크 관련 키워드 체크
    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('internet') ||
        errorString.contains('dns') ||
        errorString.contains('unreachable') ||
        errorString.contains('socketexception') ||
        errorString.contains('no address associated')) {
      return ErrorType.network;
    }
    
    // 서버 연결 관련 키워드 체크
    if (errorString.contains('server') ||
        errorString.contains('unavailable') ||
        errorString.contains('service') ||
        errorString.contains('backend') ||
        errorString.contains('gateway') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504')) {
      return ErrorType.serverConnection;
    }
    
    // 타임아웃 관련 키워드 체크
    if (errorString.contains('timeout') ||
        errorString.contains('deadline') ||
        errorString.contains('exceeded')) {
      return ErrorType.timeout;
    }
    
    // 인증 관련 키워드 체크
    if (errorString.contains('401') || 
        errorString.contains('unauthorized') ||
        errorString.contains('authentication')) {
      return ErrorType.unauthorized;
    }
    
    // 권한 관련 키워드 체크
    if (errorString.contains('403') || 
        errorString.contains('forbidden') ||
        errorString.contains('permission')) {
      return ErrorType.forbidden;
    }
    
    // 찾을 수 없음 관련 키워드 체크
    if (errorString.contains('404') || 
        errorString.contains('not found') ||
        errorString.contains('notfound')) {
      return ErrorType.notFound;
    }
    
    // 요청 제한 관련 키워드 체크
    if (errorString.contains('429') || 
        errorString.contains('rate limit') ||
        errorString.contains('too many requests')) {
      return ErrorType.rateLimited;
    }
    
    // 저장공간 관련 키워드 체크
    if (errorString.contains('storage') || 
        errorString.contains('disk') ||
        errorString.contains('space')) {
      return ErrorType.storage;
    }
    
    // 기본값은 일반적인 에러
    return ErrorType.general;
  }
  
  /// 에러 유형에 따른 사용자 친화적 메시지 반환
  static String getErrorMessage(ErrorType errorType, [ErrorContext? context]) {
    switch (errorType) {
      case ErrorType.network:
        return '인터넷 연결 상태를 확인해주세요.';
      case ErrorType.serverConnection:
        return '서버 연결이 불안정해요. 잠시 후 다시 시도해주세요.';
      case ErrorType.timeout:
        return context == ErrorContext.dictionary 
            ? '사전 검색 시간이 초과되었어요. 다시 시도해주세요.'
            : context == ErrorContext.ocr
            ? '문제가 지속되고 있습니다. 잠시 뒤에 다시 시도해 주세요.'
            : '처리 시간이 너무 오래 걸리고 있어요. 다시 시도해주세요.';
      case ErrorType.unauthorized:
        return '로그인이 필요해요. 다시 로그인해주세요.';
      case ErrorType.forbidden:
        return '이 기능을 사용할 권한이 없어요.';
      case ErrorType.notFound:
        return context == ErrorContext.dictionary 
            ? '사전에서 단어를 찾을 수 없어요.'
            : context == ErrorContext.flashcard
            ? '플래시카드를 찾을 수 없어요.'
            : '요청한 정보를 찾을 수 없어요.';
      case ErrorType.rateLimited:
        return '너무 많은 요청이 발생했어요. 잠시 후 다시 시도해주세요.';
      case ErrorType.storage:
        return '저장 공간이 부족해요. 공간을 확보한 후 다시 시도해주세요.';
      case ErrorType.permission:
        return '필요한 권한이 없어요. 설정에서 권한을 허용해주세요.';
      case ErrorType.general:
        return context == ErrorContext.dictionary 
            ? '사전 검색 중 오류가 발생했어요. 다시 시도해주세요.'
            : context == ErrorContext.flashcard
            ? '플래시카드 처리 중 오류가 발생했어요. 다시 시도해주세요.'
            : context == ErrorContext.noteEdit
            ? '노트 편집 중 오류가 발생했어요. 다시 시도해주세요.'
            : context == ErrorContext.noteDelete
            ? '노트 삭제 중 오류가 발생했어요. 다시 시도해주세요.'
            : '일시적인 문제가 발생했어요. 잠시 후 다시 시도해주세요.';
    }
  }
  
  /// 에러를 분석하고 바로 메시지 반환
  static String getMessageFromError(dynamic error, [ErrorContext? context]) {
    final errorType = analyzeError(error);
    return getErrorMessage(errorType, context);
  }
  
  /// 스낵바로 에러 메시지 표시
  static void showErrorSnackBar(BuildContext context, dynamic error, [ErrorContext? errorContext]) {
    if (!context.mounted) return;
    
    final message = getMessageFromError(error, errorContext);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '확인',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
    
    if (kDebugMode) {
      debugPrint('📢 [ErrorHandler] 스낵바 메시지 표시: $message (컨텍스트: $errorContext)');
    }
  }
  
  /// 성공 메시지 스낵바 표시
  static void showSuccessSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[600],
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    if (kDebugMode) {
      debugPrint('📢 [ErrorHandler] 성공 메시지 표시: $message');
    }
  }
  
  /// 정보 메시지 스낵바 표시
  static void showInfoSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue[600],
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    if (kDebugMode) {
      debugPrint('📢 [ErrorHandler] 정보 메시지 표시: $message');
    }
  }
  
  /// 타임아웃 단계별 메시지 반환
  static String getTimeoutMessage(int elapsedSeconds) {
    if (elapsedSeconds >= 10 && elapsedSeconds < 20) {
      return '처리 시간이 평소보다 오래 걸리고 있어요. (약 ${elapsedSeconds}초 경과)';
    } else if (elapsedSeconds >= 20 && elapsedSeconds < 30) {
      return '다시 시도 중입니다…';
    } else if (elapsedSeconds >= 30) {
      return '문제가 지속되고 있습니다. 잠시 뒤에 다시 시도해 주세요.';
    }
    return '처리 중입니다...';
  }
} 