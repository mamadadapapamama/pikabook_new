import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart'; // 🎯 Provider 추가

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/services/media/image_picker_service.dart';
import '../../../core/widgets/image_picker_bottom_sheet.dart';
import '../home_viewmodel.dart'; // 🎯 HomeViewModel import
// import '../../note/view/note_detail_screen.dart'; // 더 이상 사용하지 않음

/// ➕ HomeScreen 플로팅 액션 버튼
/// 
/// 책임:
/// - 이미지 선택 기능 (카메라 또는 갤러리)
/// - 새 노트 생성 및 이동
/// - 🎯 사용량 제한에 따른 버튼 활성화/비활성화
class HomeFloatingButton extends StatelessWidget {
  const HomeFloatingButton({super.key});

  @override
  Widget build(BuildContext context) {
    // 🎯 ViewModel의 canCreateNote 상태를 구독
    final canCreateNote = context.watch<HomeViewModel>().canCreateNote;
    
    return FloatingActionButton(
      onPressed: canCreateNote ? () => _showImagePickerOptions(context) : null,
      backgroundColor: canCreateNote ? ColorTokens.primary : Colors.grey, // 🎯 비활성화 색상
      foregroundColor: Colors.white,
      shape: const CircleBorder(),
      elevation: canCreateNote ? 6.0 : 0.0, // 🎯 비활성화 시 그림자 제거
      child: const Icon(
        Icons.add,
        size: 28,
      ),
    );
  }

  /// 📷 이미지 선택 옵션 표시
  void _showImagePickerOptions(BuildContext context) {
    if (kDebugMode) {
      debugPrint('📷 [HomeFloatingButton] 이미지 선택 옵션 표시');
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const ImagePickerBottomSheet(),
    );
  }
} 