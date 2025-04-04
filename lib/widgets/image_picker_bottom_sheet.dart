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
        // 새 로딩 다이얼로그 표시 (단순화 - 기존 다이얼로그 닫기 시도 제거)
        LoadingDialog.show(context, message: '노트 생성 중...');
        isLoadingDialogShowing = true;
      }

      // 여러 이미지로 노트 생성 (첫 번째 페이지만 처리하고 결과 반환)
      final result = await _noteService.createNoteWithMultipleImages(
        imageFiles: images,
        title: null, // 자동 타이틀 생성을 위해 null 전달
        silentProgress: true, // 진행 상황 업데이트 무시
      );

      // 결과를 먼저 저장 (네비게이션 전)
      final bool success = result['success'] == true;
      final String? noteId = result['noteId'] as String?;
      final bool isProcessingBackground = result['isProcessingBackground'] ?? false;
      final String message = result['message'] ?? '노트 생성에 실패했습니다.';

      // 로딩 다이얼로그 닫기 (단순화)
      if (isLoadingDialogShowing && context.mounted) {
        // 네비게이터 작업 감소를 위해 간단한 방식으로만 닫기
        try {
          LoadingDialog.hide(context);
          debugPrint("로딩 다이얼로그 닫기 시도");
          
          // 잠시 대기하여 다이얼로그가 닫힐 시간 제공
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (e) {
          debugPrint("로딩 다이얼로그 닫기 중 오류: $e");
        } finally {
          isLoadingDialogShowing = false;
        }
      }

      // 결과에 따라 다음 화면으로 이동 또는 오류 메시지 표시
      if (success && noteId != null && context.mounted) {
        debugPrint("노트 상세 화면으로 이동 시도");
        
        // 비동기 작업을 사용하여 UI 스레드 차단 방지
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => NoteDetailScreen(
                  noteId: noteId,
                  isProcessingBackground: isProcessingBackground,
                ),
              ),
            );
            debugPrint("노트 상세 화면으로 이동 완료");
          }
        });
      } else if (context.mounted) {
        // 오류 메시지 표시
        debugPrint("노트 생성 실패: $message");
        
        // 비동기 작업을 사용하여 UI 스레드 차단 방지
        WidgetsBinding.instance.addPostFrameCallback((_) {
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
        });
      }
    } catch (e) {
      debugPrint("노트 생성 중 오류 발생: $e");
      
      // 오류 발생 시 로딩 다이얼로그 닫기
      if (isLoadingDialogShowing && context.mounted) {
        try {
          LoadingDialog.hide(context);
          debugPrint("오류 발생 후 로딩 다이얼로그 닫힘");
          
          // 잠시 대기
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (closeError) {
          debugPrint("오류 발생 후 로딩 다이얼로그 닫기 중 오류: $closeError");
        } finally {
          isLoadingDialogShowing = false;
        }
        
        // 비동기 작업을 사용하여 UI 스레드 차단 방지
        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('노트 생성 중 오류가 발생했습니다: $e'),
                  backgroundColor: ColorTokens.error,
                  behavior: UITokens.snackBarTheme.behavior,
                  shape: UITokens.snackBarTheme.shape,
                ),
              );
            }
          });
        }
      }
    }
  }
} 