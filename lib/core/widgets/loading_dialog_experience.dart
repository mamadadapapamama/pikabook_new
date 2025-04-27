import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'dart:async';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import 'dot_loading_indicator.dart';

/// 다이얼로그 형태의 로딩 경험을 제공하는 클래스들(현재는 노트 생성 전용)


/// 노트 생성 중 표시할 로딩 다이얼로그
/// Pikabook 스타일의 로딩 UI를 제공합니다.
class NoteCreationLoader {
  static bool _isVisible = false;
  static Timer? _timeoutTimer;
  
  /// 노트 생성 로더 표시
  static Future<void> show(
    BuildContext context, {
    String message = '스마트한 학습 노트를 만들고 있어요.\n잠시만 기다려 주세요! 조금 시간이 걸릴수 있어요.',
    int timeoutSeconds = 20, // 타임아웃 시간 (초 단위)
  }) async {

    // 성능 오버레이 및 디버그 타이머 비활성화
      timeDilation = 1.0;
    
    if (!context.mounted) {
      if (kDebugMode) {
      debugPrint('컨텍스트가 더 이상 유효하지 않습니다');
      }
      return;
    }
    
    // 이미 로더가 표시되고 있는지 확인
    if (_isVisible) {
      if (kDebugMode) {
      debugPrint('로더가 이미 표시되고 있습니다');
      }
      return;
    }
    
    _isVisible = true;
    
    // 타임아웃 설정 - 지정된 시간 후 자동으로 닫힘
    _timeoutTimer?.cancel();
    if (timeoutSeconds > 0) {
      _timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () {
        // 타임아웃 시 안전하게 제거
        if (_isVisible) {
          if (kDebugMode) {
          debugPrint('로더가 타임아웃으로 자동 종료됨');
          }
          if (context.mounted) hide(context);
        }
      });
    }
    
    try {
      // WidgetsBinding을 사용하여 다음 프레임에서 다이얼로그 표시
      // (애니메이션 중첩 방지)
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted || !_isVisible) return;
        
        try {
          await showDialog(
            context: context,
            barrierDismissible: false,
            barrierColor: Colors.black.withOpacity(0.5),
            useSafeArea: true,
            builder: (dialogContext) => WillPopScope(
              onWillPop: () async => false, // 뒤로 가기 방지
              child: Theme(
                // 성능 오버레이 비활성화를 위한 명시적 테마 설정
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
                            // 도트 애니메이션
                            const DotLoadingIndicator(),
                            
                            const SizedBox(width: 12),
                            
                            // 피카북 새 캐릭터 (고정된 상태)
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
                        
                        // 텍스트 섹션
                        Text(
                          message,
                          style: TypographyTokens.body1.copyWith(
                            height: 1.4,
                            color: ColorTokens.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ).then((_) {
            _timeoutTimer?.cancel();
            _isVisible = false;
          });
        } catch (dialogError) {
          if (kDebugMode) {
          debugPrint('다이얼로그 표시 중 내부 오류: $dialogError');
          }
          _timeoutTimer?.cancel();
          _isVisible = false;
        }
      });
    } catch (e) {
      if (kDebugMode) {
      debugPrint('노트 생성 로더 표시 중 오류: $e');
      }
      _timeoutTimer?.cancel();
      _isVisible = false;
    }
  }

  /// 노트 생성 로더 숨기기
  static void hide(BuildContext context) {
    if (!context.mounted) return;
    
    try {
      // 안전하게 다이얼로그 닫기
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
      _timeoutTimer?.cancel();
      _isVisible = false;
    }
  }
  
  /// 로더가 표시 중인지 확인하고 표시 중이면 강제로 닫음
  /// 어떤 상황에서든 로딩 다이얼로그가 화면에 남아있지 않도록 보장
  static void ensureHidden(BuildContext context) {
    // 로더가 표시 중인지 확인
    if (_isVisible) {
      if (kDebugMode) {
        debugPrint('로딩 다이얼로그가 표시 중이므로 강제로 닫습니다');
      }
      
      try {
        // 안전하게 다이얼로그 닫기 시도
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('강제 다이얼로그 종료 중 오류: $e');
        }
      } finally {
        // 상태 초기화
        _timeoutTimer?.cancel();
        _isVisible = false;
      }
    } else {
      if (kDebugMode) {
        debugPrint('로딩 다이얼로그가 이미 닫혀 있습니다');
      }
    }
  }
  
  /// 로더가 표시 중인지 확인
  static bool isShowing() {
    return _isVisible;
  }
} 