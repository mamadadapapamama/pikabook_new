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
import '../services/usage_limit_service.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

class ImagePickerBottomSheet extends StatefulWidget {
  const ImagePickerBottomSheet({Key? key}) : super(key: key);

  @override
  State<ImagePickerBottomSheet> createState() => _ImagePickerBottomSheetState();
}

class _ImagePickerBottomSheetState extends State<ImagePickerBottomSheet> {
  final ImageService _imageService = ImageService();
  final NoteService _noteService = NoteService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  bool _isButtonDisabled = false;
  String _limitTooltip = '';
  
  @override
  void initState() {
    super.initState();
    _checkUsageLimits();
  }
  
  // 사용량 한도 확인
  Future<void> _checkUsageLimits() async {
    try {
      // 사용량 제한 상태 확인
      final limitStatus = await _usageLimitService.checkFreeLimits();
      
      // OCR, 번역, 저장 공간 중 하나라도 제한에 도달했는지 확인
      final bool ocrLimitReached = limitStatus['ocrLimitReached'] == true;
      final bool translationLimitReached = limitStatus['translationLimitReached'] == true;
      final bool storageLimitReached = limitStatus['storageLimitReached'] == true;
      
      if (mounted) {
        setState(() {
          // OCR, 번역, 저장 공간 중 하나라도 한도 도달 시 버튼 비활성화
          _isButtonDisabled = ocrLimitReached || translationLimitReached || storageLimitReached;
          
          // 툴팁 메시지 설정
          if (ocrLimitReached) {
            _limitTooltip = '무료 OCR 사용량이 초과되었습니다. 다음 달까지 기다리거나 프리미엄으로 업그레이드하세요.';
          } else if (translationLimitReached) {
            _limitTooltip = '무료 번역 사용량이 초과되었습니다. 다음 달까지 기다리거나 프리미엄으로 업그레이드하세요.';
          } else if (storageLimitReached) {
            _limitTooltip = '무료 저장 공간이 가득 찼습니다. 일부 노트를 삭제하거나 프리미엄으로 업그레이드하세요.';
          }
        });
      }
    } catch (e) {
      debugPrint('사용량 확인 중 오류 발생: $e');
    }
  }

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
                _isButtonDisabled
                ? Tooltip(
                    message: _limitTooltip,
                    child: PikaButton(
                      text: '갤러리에서 선택',
                      variant: PikaButtonVariant.outline,
                      leadingIcon: Icon(Icons.photo_library, color: ColorTokens.disabled),
                      onPressed: null, // 버튼 비활성화
                      isFullWidth: true,
                    ),
                  )
                : PikaButton(
                    text: '갤러리에서 선택',
                    variant: PikaButtonVariant.outline,
                    leadingIcon: Icon(Icons.photo_library, color: ColorTokens.primary),
                    onPressed: () => _pickImagesAndCreateNote(context),
                    isFullWidth: true,
                  ),
                
                const SizedBox(height: 16),
                
                _isButtonDisabled
                ? Tooltip(
                    message: _limitTooltip,
                    child: PikaButton(
                      text: '카메라로 촬영',
                      variant: PikaButtonVariant.outline,
                      leadingIcon: Icon(Icons.camera_alt, color: ColorTokens.disabled),
                      onPressed: null, // 버튼 비활성화
                      isFullWidth: true,
                    ),
                  )
                : PikaButton(
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
    // 바텀 시트를 닫기 전에 컨텍스트 저장
    final rootContext = Navigator.of(context).context;
    
    // 바텀 시트 닫기
    Navigator.pop(context);
    
    // 적절한 지연 추가 (iOS에서 필요)
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
      // 이미지 선택
      final images = await _imageService.pickMultipleImages();
      
      // 이미지가 선택되었고 컨텍스트가 유효한지 확인
      if (images.isNotEmpty && rootContext.mounted) {
        // 노트 생성 진행
        await _createNoteWithImages(rootContext, images);
      }
    } catch (e) {
      debugPrint('이미지 선택 중 오류 발생: $e');
      
      // 컨텍스트가 유효한지 확인
      if (rootContext.mounted) {
        ScaffoldMessenger.of(rootContext).showSnackBar(
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
    final rootContext = Navigator.of(context).context;
    
    // 바텀 시트 닫기
    Navigator.pop(context);
    
    // 적절한 지연 추가 (iOS에서 필요)
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
      // 카메라로 사진 촬영
      final image = await _imageService.pickImage(source: ImageSource.camera);
      
      // 이미지가 선택되었고 컨텍스트가 유효한지 확인
      if (image != null && rootContext.mounted) {
        // 노트 생성 진행
        await _createNoteWithImages(rootContext, [image]);
      }
    } catch (e) {
      debugPrint('카메라 촬영 중 오류 발생: $e');
      
      // 컨텍스트가 유효한지 확인
      if (rootContext.mounted) {
        ScaffoldMessenger.of(rootContext).showSnackBar(
          SnackBar(
            content: Text('카메라 촬영 중 오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
            behavior: UITokens.snackBarTheme.behavior,
            shape: UITokens.snackBarTheme.shape,
          ),
        );
      }
    }
  }
  
  Future<void> _createNoteWithImages(BuildContext context, List<File> images) async {
    // 이미지가 선택되었는지 확인
    if (images.isEmpty) {
      _showSnackBar(context, '이미지를 선택해주세요.');
      return;
    }

    try {
      // 로딩 다이얼로그 표시
      if (context.mounted) {
        LoadingDialog.show(context, message: '노트 생성 중...');
      }

      debugPrint('노트 생성 시작: ${images.length}개 이미지');
      
      // Firebase 초기화 확인
      try {
        Firebase.app();
        debugPrint('Firebase 초기화 확인 성공');
      } catch (e) {
        debugPrint('Firebase가 초기화되지 않았습니다: $e');
        if (context.mounted) {
          LoadingDialog.hide(context); // 로딩 다이얼로그 닫기
          _showSnackBar(context, 'Firebase 초기화에 실패했습니다. 앱을 재시작해주세요.');
        }
        return;
      }

      // 노트 생성
      final result = await _noteService.createNoteWithMultipleImages(
        imageFiles: images,
        title: null,
        silentProgress: true,
        waitForFirstPageProcessing: true, // 첫 페이지 처리 완료까지 대기
      );

      // 결과 처리
      if (result == null) {
        debugPrint('노트 생성 실패: 결과가 null입니다');
        if (context.mounted) {
          LoadingDialog.hide(context); // 로딩 다이얼로그 닫기
          _showSnackBar(context, '노트 생성에 실패했습니다.');
        }
        return;
      }

      final noteId = result['noteId'];
      if (noteId == null || noteId.isEmpty) {
        debugPrint('노트 생성 실패: 결과에 유효한 noteId가 없습니다 - $result');
        if (context.mounted) {
          LoadingDialog.hide(context); // 로딩 다이얼로그 닫기
          _showSnackBar(context, '노트 ID 생성에 실패했습니다.');
        }
        return;
      }

      debugPrint('노트 생성 성공: noteId=$noteId');
      
      // 약간의 지연 후 노트 상세 화면으로 이동
      await Future.delayed(const Duration(milliseconds: 500));

      if (context.mounted) {
        LoadingDialog.hide(context); // 로딩 다이얼로그 닫기
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => NoteDetailScreen(
              noteId: noteId,
              isProcessingBackground: false,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('노트 생성 중 예외 발생: $e');
      if (context.mounted) {
        LoadingDialog.hide(context); // 로딩 다이얼로그 닫기
        _showSnackBar(context, '노트 생성 중 오류가 발생했습니다: ${e.toString()}');
      }
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ColorTokens.error,
        behavior: UITokens.snackBarTheme.behavior,
        shape: UITokens.snackBarTheme.shape,
      ),
    );
  }
} 