import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'pikabook_loader.dart';
import 'dart:async';

/// 로딩 다이얼로그를 표시하는 유틸리티 클래스
///
/// 장시간의 작업이 진행될 때 전체 화면을 덮는 로딩 다이얼로그를 표시합니다.
/// 내부적으로 PikabookLoader를 사용하여 디자인에 맞게 구현되었습니다.
class LoadingDialog {
  static bool _isShowing = false;
  static OverlayEntry? _overlayEntry;

  /// 로딩 다이얼로그를 표시하는 정적 메서드
  static void show(BuildContext context, {String? message}) {
    if (!context.mounted) {
      return;
    }

    // 애니메이션 타이머 출력 방지
    timeDilation = 1.0;

    // 이미 표시 중이면 제거 후 다시 표시
    if (_isShowing) {
      hide(context);
    }

    // 상태 업데이트
    _isShowing = true;

    // OverlayEntry로 로딩 화면 표시 (UI 출력 문제 없음)
    _showWithOverlay(context, message: message);
  }

  // OverlayEntry를 사용한 로딩 다이얼로그 표시
  static void _showWithOverlay(BuildContext context, {String? message}) {
    if (!context.mounted) return;
    
    final overlay = Overlay.of(context);
    if (overlay == null) return;
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // 전체 화면 반투명 배경
            Positioned.fill(
              child: Container(
                color: Colors.black54,
              ),
            ),
            // 중앙 로딩 다이얼로그
            Center(
              child: PikabookLoader(
                title: '스마트한 학습 노트를 만들고 있어요.',
                subtitle: message ?? '잠시만 기다려 주세요!',
              ),
            ),
          ],
        ),
      ),
    );
    
    overlay.insert(_overlayEntry!);
  }
  
  /// 로딩 다이얼로그를 닫는 정적 메서드
  static void hide(BuildContext context) {
    // 다이얼로그가 표시되어 있지 않으면 아무 작업도 하지 않음
    if (!_isShowing) {
      return;
    }
    
    // 상태 업데이트
    _isShowing = false;
    
    // OverlayEntry가 있으면 제거
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
  }
} 