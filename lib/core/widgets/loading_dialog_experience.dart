import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'dart:async';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../utils/timeout_manager.dart';
import '../utils/error_handler.dart';
import 'dot_loading_indicator.dart';

/// 다이얼로그 형태의 로딩 경험을 제공하는 클래스들(현재는 노트 생성 전용)

/// 노트 생성 중 표시할 로딩 다이얼로그
/// Pikabook 스타일의 로딩 UI를 제공합니다.
class NoteCreationLoader {
  static bool _isVisible = false;
  static BuildContext? _lastContext;
  static TimeoutManager? _timeoutManager;
  static String _currentMessage = '';
  static VoidCallback? _onTimeoutCallback;
  static ValueNotifier<String> _messageNotifier = ValueNotifier<String>('');
  
  /// 로더가 현재 표시 중인지 확인
  static bool get isVisible => _isVisible;
  
  /// 노트 생성 로더 표시 (향상된 타임아웃 처리)
  static Future<void> show(
    BuildContext context, {
    String message = '스마트한 학습 노트를 만들고 있어요.\n잠시만 기다려 주세요!',
    int timeoutSeconds = 30,
    VoidCallback? onTimeout,
  }) async {
    if (_isVisible) {
      if (kDebugMode) {
        debugPrint('로딩 다이얼로그가 이미 표시 중입니다.');
      }
      if (context.mounted) {
        _lastContext = context;
      }
      return;
    }
    
    _lastContext = context;
    _isVisible = true;
    _currentMessage = message;
    _onTimeoutCallback = onTimeout;
    _messageNotifier.value = message;
    
    timeDilation = 1.0;
    
    if (!context.mounted) {
      if (kDebugMode) {
        debugPrint('컨텍스트가 더 이상 유효하지 않습니다');
      }
      return;
    }

    // 타임아웃 매니저 설정
    _timeoutManager?.dispose();
    _timeoutManager = TimeoutManager();
    
    _timeoutManager!.start(
      timeoutSeconds: timeoutSeconds,
      identifier: 'LoadingDialog',
      onProgress: (elapsedSeconds) {
        // 단계별 메시지 업데이트
        if (_timeoutManager!.shouldUpdateMessage()) {
          final newMessage = _timeoutManager!.getCurrentMessage(_currentMessage);
          _messageNotifier.value = newMessage;
          
          if (kDebugMode) {
            debugPrint('📝 [NoteCreationLoader] 메시지 업데이트: $newMessage');
          }
        }
      },
      onTimeout: () {
        // 타임아웃 발생시 처리
        if (kDebugMode) {
          debugPrint('⏰ [NoteCreationLoader] 타임아웃 발생');
        }
        
        if (_lastContext != null && _lastContext!.mounted) {
          // 모달 닫기
          hide(_lastContext!);
          
          // 스낵바로 타임아웃 에러 메시지 표시
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_lastContext!.mounted) {
              ScaffoldMessenger.of(_lastContext!).showSnackBar(
                SnackBar(
                  content: const Text('문제가 지속되고 있어요. 잠시 뒤에 다시 시도해 주세요.'),
                  backgroundColor: Colors.red[600],
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                  action: SnackBarAction(
                    label: '확인',
                    textColor: Colors.white,
                    onPressed: () {
                      ScaffoldMessenger.of(_lastContext!).hideCurrentSnackBar();
                    },
                  ),
                ),
              );
              
              if (kDebugMode) {
                debugPrint('📢 [NoteCreationLoader] 타임아웃 스낵바 메시지 표시');
              }
            }
          });
          
          // 기존 타임아웃 콜백 호출 (추가 에러 처리가 필요한 경우)
          _onTimeoutCallback?.call();
        }
      },
    );

    try {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted || !_isVisible) return;
        
        try {
          await showDialog(
            context: context,
            barrierDismissible: false,
            barrierColor: Colors.black.withOpacity(0.4),
            useSafeArea: true,
            builder: (dialogContext) => WillPopScope(
              onWillPop: () async => false,
              child: Theme(
                data: ThemeData(
                  scaffoldBackgroundColor: Colors.white,
                  colorScheme: Theme.of(context).colorScheme,
                  brightness: Theme.of(context).brightness,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                      width: 300,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 도트 로딩 인디케이터
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const DotLoadingIndicator(),
                              const SizedBox(width: 12),
                              Image.asset(
                                'assets/images/pikabook_bird.png',
                                width: 40,
                                height: 40,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: ColorTokens.primary.withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.auto_awesome,
                                      color: ColorTokens.primary,
                                      size: 24,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // 동적 메시지 표시
                          ValueListenableBuilder<String>(
                            valueListenable: _messageNotifier,
                            builder: (context, message, child) {
                              return Text(
                                message,
                                style: TypographyTokens.body1.copyWith(
                                  height: 1.4,
                                  color: ColorTokens.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ).then((_) {
            _forceResetState();
          });
        } catch (dialogError) {
          if (kDebugMode) {
            debugPrint('다이얼로그 표시 중 내부 오류: $dialogError');
          }
          _forceResetState();
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('노트 생성 로더 표시 중 오류: $e');
      }
      _forceResetState();
    }
  }

  /// 메시지 업데이트 (진행 중에도 가능)
  static void updateMessage(String newMessage) {
    if (_isVisible) {
      _messageNotifier.value = newMessage;
      if (kDebugMode) {
        debugPrint('📝 [NoteCreationLoader] 실시간 메시지 업데이트: $newMessage');
      }
    }
  }

  /// 노트 생성 로더 숨기기
  static void hide(BuildContext context) {
    if (!context.mounted) {
      _forceResetState();
      return;
    }
    
    try {
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      } else {
        if (kDebugMode) {
          debugPrint('숨길 다이얼로그가 없습니다');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('노트 생성 로더 숨기기 중 오류: $e');
      }
    } finally {
      _forceResetState();
    }
  }

  /// 에러 발생시 로딩 다이얼로그 닫고 스낵바 표시
  static void hideWithError(BuildContext context, dynamic error) {
    if (!context.mounted) {
      _forceResetState();
      return;
    }

    // 로딩 다이얼로그 닫기
    hide(context);
    
    // 에러 타입에 따른 스낵바 표시
    Future.delayed(const Duration(milliseconds: 300), () {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(context, error);
      }
    });
  }
  
  /// 상태 강제 초기화
  static void _forceResetState() {
    _timeoutManager?.dispose();
    _timeoutManager = null;
    _isVisible = false;
    _currentMessage = '';
    _onTimeoutCallback = null;
    _messageNotifier.value = '';
  }
  
  /// 로더 강제 종료
  static void ensureHidden(BuildContext context) {
    if (_isVisible) {
      if (kDebugMode) {
        debugPrint('로딩 다이얼로그 강제 종료');
      }
      
      try {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('강제 다이얼로그 종료 중 오류: $e');
        }
      } finally {
        _forceResetState();
      }
    }
  }
  
  /// 리소스 정리
  static void dispose() {
    _forceResetState();
    _lastContext = null;
  }
  
  /// 현재 표시 상태 확인
  static bool isShowing() {
    return _isVisible;
  }
} 