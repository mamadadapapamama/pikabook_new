import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/services/media/image_picker_service.dart';
import '../../../core/widgets/image_picker_bottom_sheet.dart';
import '../../note/view/note_detail_screen.dart';

/// ➕ HomeScreen 플로팅 액션 버튼
/// 
/// 책임:
/// - 이미지 선택 기능 (카메라 또는 갤러리)
/// - 새 노트 생성 및 이동
class HomeFloatingButton extends StatelessWidget {
  const HomeFloatingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => _showImagePickerOptions(context),
      backgroundColor: ColorTokens.primary,
      foregroundColor: Colors.white,
      shape: const CircleBorder(),
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