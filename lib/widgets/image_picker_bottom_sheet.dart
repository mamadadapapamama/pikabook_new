import 'package:flutter/material.dart';
import 'dart:io';
import '../services/image_service.dart';
import '../services/note_service.dart';
import '../views/screens/note_detail_screen.dart';
import '../widgets/loading_dialog.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/ui_tokens.dart';
import '../widgets/common/pika_button.dart';
import 'package:image_picker/image_picker.dart';

class ImagePickerBottomSheet extends StatefulWidget {
  const ImagePickerBottomSheet({Key? key}) : super(key: key);

  @override
  State<ImagePickerBottomSheet> createState() => _ImagePickerBottomSheetState();
}

class _ImagePickerBottomSheetState extends State<ImagePickerBottomSheet> {
  final ImageService _imageService = ImageService();
  final NoteService _noteService = NoteService();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 헤더 (제목 + X 버튼)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '스마트 노트 만들기',
                  style: TypographyTokens.subtitle2.copyWith(
                    color: Colors.black,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.close,
                    size: 24,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // 갤러리 및 카메라 옵션 버튼
            Column(
              children: [
                PikaButton(
                  text: '갤러리에서 선택',
                  variant: PikaButtonVariant.outline,
                  leadingIcon: Icon(Icons.photo_library, color: ColorTokens.primary),
                  onPressed: () => _pickImagesAndCreateNote(context),
                  isFullWidth: true,
                ),
                
                const SizedBox(height: 16),
                
                PikaButton(
                  text: '카메라로 촬영',
                  variant: PikaButtonVariant.outline,
                  leadingIcon: Icon(Icons.camera_alt, color: ColorTokens.primary),
                  onPressed: () => _takePhotoAndCreateNote(context),
                  isFullWidth: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImagesAndCreateNote(BuildContext context) async {
    // 바텀 시트를 닫기 전에 전역 키를 사용하여 컨텍스트 저장
    final navigatorContext = Navigator.of(context).context;

    Navigator.pop(context); // 바텀 시트 닫기

    try {
      final images = await _imageService.pickMultipleImages();

      if (images.isNotEmpty) {
        // 저장된 컨텍스트를 사용하여 로딩 다이얼로그 표시
        if (navigatorContext.mounted) {
          LoadingDialog.show(navigatorContext, message: '노트 생성 중...');
          await _createNoteWithImages(navigatorContext, images);
        }
      }
    } catch (e) {
      if (navigatorContext.mounted) {
        // 오류 발생 시 로딩 다이얼로그 닫기
        LoadingDialog.hide(navigatorContext);
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          SnackBar(
            content: Text('이미지 선택 중 오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
            behavior: UITokens.snackBarTheme.behavior,
            shape: UITokens.snackBarTheme.shape,
          ),
        );
      }
    }
  }

  Future<void> _takePhotoAndCreateNote(BuildContext context) async {
    // 바텀 시트를 닫기 전에 전역 키를 사용하여 컨텍스트 저장
    final navigatorContext = Navigator.of(context).context;

    Navigator.pop(context); // 바텀 시트 닫기

    try {
      final image = await _imageService.pickImage(source: ImageSource.camera);

      if (image != null) {
        // 저장된 컨텍스트를 사용하여 로딩 다이얼로그 표시
        if (navigatorContext.mounted) {
          LoadingDialog.show(navigatorContext, message: '노트 생성 중...');
          await _createNoteWithImages(navigatorContext, [image]);
        }
      } else {
        // 사용자가 사진 촬영을 취소한 경우
        if (navigatorContext.mounted) {
          ScaffoldMessenger.of(navigatorContext).showSnackBar(
            SnackBar(
              content: const Text('사진 촬영이 취소되었습니다.'),
              backgroundColor: ColorTokens.secondary,
              behavior: UITokens.snackBarTheme.behavior,
              shape: UITokens.snackBarTheme.shape,
            ),
          );
        }
      }
    } catch (e) {
      if (navigatorContext.mounted) {
        // 오류 발생 시 로딩 다이얼로그 닫기
        LoadingDialog.hide(navigatorContext);
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          SnackBar(
            content: Text('사진 촬영 중 오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
            behavior: UITokens.snackBarTheme.behavior,
            shape: UITokens.snackBarTheme.shape,
          ),
        );
      }
    }
  }

  Future<void> _createNoteWithImages(
      BuildContext context, List<File> images) async {
    if (images.isEmpty) return;

    // 로딩 다이얼로그 표시 여부를 추적하는 변수
    bool isLoadingDialogShowing = false;

    try {
      debugPrint("노트 생성 시작: ${images.length}개 이미지");

      // 로딩 다이얼로그 표시 - 첫 페이지 로딩까지만 표시
      if (context.mounted) {
        LoadingDialog.show(context, message: '노트 생성 중...');
        isLoadingDialogShowing = true;
      }

      // 여러 이미지로 노트 생성 (첫 번째 페이지만 처리하고 결과 반환)
      final result = await _noteService.createNoteWithMultipleImages(
        imageFiles: images,
        title: null, // 자동 타이틀 생성을 위해 null 전달
        silentProgress: true, // 진행 상황 업데이트 무시
      );

      // 로딩 다이얼로그 닫기 (로직 개선 - 확실하게 닫히도록)
      if (context.mounted && isLoadingDialogShowing) {
        try {
          LoadingDialog.hide(context);
          debugPrint("로딩 다이얼로그 명시적으로 닫힘");
        } catch (e) {
          debugPrint("로딩 다이얼로그 닫기 중 오류: $e");
        } finally {
          // 상태 업데이트
          isLoadingDialogShowing = false;
          // 약간의 지연을 주어 다이얼로그가 확실히 닫히도록 함
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      if (result['success'] == true && result['noteId'] != null) {
        final String noteId = result['noteId'] as String;

        // 노트 상세 화면으로 이동
        if (context.mounted) {
          debugPrint("노트 상세 화면으로 이동 시도");

          // 화면 전환
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => NoteDetailScreen(
                noteId: noteId,
                isProcessingBackground: result['isProcessingBackground'] ?? false,
              ),
            ),
          );

          debugPrint("노트 상세 화면으로 이동 완료");
        }
      } else {
        // 오류 메시지 표시
        final message = result['message'] ?? '노트 생성에 실패했습니다.';
        debugPrint("노트 생성 실패: $message");

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message.toString()),
              backgroundColor: ColorTokens.error,
              behavior: UITokens.snackBarTheme.behavior,
              shape: UITokens.snackBarTheme.shape,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("노트 생성 중 오류 발생: $e");

      // 오류 발생 시 로딩 다이얼로그 닫고 오류 메시지 표시
      if (context.mounted && isLoadingDialogShowing) {
        try {
          LoadingDialog.hide(context);
          debugPrint("오류 발생 후 로딩 다이얼로그 닫힘");
        } catch (closeError) {
          debugPrint("오류 발생 후 로딩 다이얼로그 닫기 중 오류: $closeError");
        } finally {
          isLoadingDialogShowing = false;
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('노트 생성 중 오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
            behavior: UITokens.snackBarTheme.behavior,
            shape: UITokens.snackBarTheme.shape,
          ),
        );
      }
    }
  }
} 