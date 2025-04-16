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
                    onPressed: () => _selectGalleryImages(context),
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
                    onPressed: () => _takeCameraPhoto(context),
                    isFullWidth: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 이미지 선택 및 노트 생성 처리
  Future<void> _selectAndCreateNote(BuildContext context) async {
    try {
      // Firebase 초기화 확인 - 직접 Firebase 객체 사용
      try {
        Firebase.app();
      } catch (e) {
        // Firebase 초기화 실패 시 에러 메시지 표시
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('서비스 연결에 실패했습니다. 잠시 후 다시 시도해주세요.')),
          );
        }
        return;
      }
      
      // 바텀 시트 닫기 - 이미지 선택 전에 닫아서 화면 전환 문제 방지
      if (context.mounted) {
        Navigator.pop(context);
        
        // 약간의 지연 후 이미지 선택 다이얼로그 열기
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      if (!context.mounted) return;
      
      // 갤러리에서 이미지 선택 (기본값)
      await _selectGalleryImages(context);
    } catch (e) {
      debugPrint('이미지 선택 및 노트 생성 중 오류: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생했습니다: $e')),
        );
      }
    }
  }
  
  /// 갤러리에서 이미지 선택
  Future<void> _selectGalleryImages(BuildContext context) async {
    try {
      // Firebase 초기화 확인
      try {
        Firebase.app();
      } catch (e) {
        // Firebase 초기화 실패 시 에러 메시지 표시
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('서비스 연결에 실패했습니다. 잠시 후 다시 시도해주세요.')),
          );
        }
        return;
      }
      
      // 바텀 시트 닫기
      if (context.mounted) {
        Navigator.pop(context);
        // 약간의 지연 추가
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      if (!context.mounted) return;
      
      // 갤러리에서 이미지 선택
      final ImagePicker picker = ImagePicker();
      final List<XFile> pickedFiles = await picker.pickMultiImage(
        requestFullMetadata: false, // iOS에서 오류 방지
      );
      
      // 이미지 선택 취소 처리
      if (pickedFiles.isEmpty) {
        debugPrint('이미지 선택이 취소되었습니다.');
        return;
      }
      
      // File 객체로 변환
      final List<File> imageFiles = pickedFiles
          .map((xFile) => File(xFile.path))
          .where((file) => file.existsSync() && file.lengthSync() > 0)
          .toList();
      
      if (imageFiles.isEmpty) {
        debugPrint('선택된 이미지가 없거나 유효하지 않습니다.');
        return;
      }
      
      // 이미지로 노트 생성
      if (context.mounted) {
        await _createNoteWithImages(context, imageFiles);
      }
    } catch (e) {
      debugPrint('갤러리 이미지 선택 중 오류: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 선택 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
  
  /// 카메라로 사진 촬영
  Future<void> _takeCameraPhoto(BuildContext context) async {
    try {
      // Firebase 초기화 확인
      try {
        Firebase.app();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('서비스 연결에 실패했습니다. 잠시 후 다시 시도해주세요.')),
          );
        }
        return;
      }
      
      // 바텀 시트 닫기
      if (context.mounted) {
        Navigator.pop(context);
        // 약간의 지연 추가
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      if (!context.mounted) return;
      
      // 카메라로 사진 촬영
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        requestFullMetadata: false, // iOS에서 오류 방지
      );
      
      // 사진 촬영 취소 처리
      if (photo == null) {
        debugPrint('카메라 촬영이 취소되었습니다.');
        return;
      }
      
      // File 객체로 변환
      final File imageFile = File(photo.path);
      if (!imageFile.existsSync() || imageFile.lengthSync() == 0) {
        debugPrint('촬영된 이미지가 유효하지 않습니다.');
        return;
      }
      
      // 이미지로 노트 생성
      if (context.mounted) {
        await _createNoteWithImages(context, [imageFile]);
      }
    } catch (e) {
      debugPrint('카메라 촬영 중 오류: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('카메라 촬영 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
  
  /// 선택한 이미지로 노트 생성
  Future<void> _createNoteWithImages(BuildContext context, List<File> imageFiles) async {
    debugPrint('노트 생성 시작: ${imageFiles.length}개 이미지');
    
    if (imageFiles.isEmpty) {
      debugPrint('이미지가 없어 노트 생성을 취소합니다.');
      return;
    }
    
    try {
      // 로딩 다이얼로그 표시
      if (context.mounted) {
        LoadingDialog.show(context, message: '노트 생성 중...');
      }
      
      // Firebase 초기화 확인 (다시 한번 확인)
      try {
        Firebase.app();
      } catch (e) {
        // Firebase 초기화 실패 시 로딩 숨기고 에러 메시지 표시
        LoadingDialog.hide();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('서비스 연결에 실패했습니다. 잠시 후 다시 시도해주세요.')),
          );
        }
        return;
      }
      
      // 노트 생성 호출
      final result = await _noteService.createNoteWithMultipleImages(
        imageFiles: imageFiles,
        waitForFirstPageProcessing: true,
      );
      
      // 로딩 다이얼로그 숨기기
      LoadingDialog.hide();
      
      // 결과 처리
      if (result['success'] == true) {
        final String? createdNoteId = result['noteId'] as String?;
        
        // null 체크 추가
        if (createdNoteId != null && createdNoteId.isNotEmpty) {
          if (context.mounted) {
            // 노트 상세 화면으로 이동 (지연 추가)
            await Future.delayed(const Duration(milliseconds: 300));
            
            if (context.mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => NoteDetailScreen(noteId: createdNoteId),
                ),
              );
            }
          }
        } else {
          debugPrint('생성된 노트 ID가 null이거나 비어 있습니다.');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('노트 생성에 실패했습니다. 다시 시도해 주세요.')),
            );
          }
        }
      } else {
        // 실패 메시지 표시
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] as String? ?? '노트 생성에 실패했습니다.')),
          );
        }
      }
    } catch (e) {
      // 로딩 다이얼로그 숨기기
      LoadingDialog.hide();
      
      debugPrint('노트 생성 중 오류: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 생성 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
} 