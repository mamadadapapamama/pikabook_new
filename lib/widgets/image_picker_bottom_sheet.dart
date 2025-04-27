import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'dart:io';
import 'dart:async';
import '../core/services/common/usage_limit_service.dart';
import '../core/theme/tokens/color_tokens.dart';
import '../core/theme/tokens/typography_tokens.dart';
import '../core/widgets/pika_button.dart';
import 'package:image_picker/image_picker.dart';
import '../core/services/workflow/note_creation_workflow.dart';

class ImagePickerBottomSheet extends StatefulWidget {
  const ImagePickerBottomSheet({Key? key}) : super(key: key);

  @override
  State<ImagePickerBottomSheet> createState() => _ImagePickerBottomSheetState();
}

class _ImagePickerBottomSheetState extends State<ImagePickerBottomSheet> {
  final UsageLimitService _usageLimitService = UsageLimitService();
  final NoteCreationWorkflow _noteCreationWorkflow = NoteCreationWorkflow();
  final ImagePicker _picker = ImagePicker();
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
      final limitStatus = await _usageLimitService.checkFreeLimits();
      
      final bool ocrLimitReached = limitStatus['ocrLimitReached'] == true;
      final bool translationLimitReached = limitStatus['translationLimitReached'] == true;
      final bool storageLimitReached = limitStatus['storageLimitReached'] == true;
      
      if (mounted) {
        setState(() {
          _isButtonDisabled = ocrLimitReached || translationLimitReached || storageLimitReached;
          
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
      if (kDebugMode) {
        debugPrint('사용량 확인 중 오류 발생: $e');
      }
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
                      onPressed: null,
                      isFullWidth: true,
                    ),
                  )
                : PikaButton(
                    text: '갤러리에서 선택',
                    variant: PikaButtonVariant.outline,
                    leadingIcon: Icon(Icons.photo_library, color: ColorTokens.primary),
                    onPressed: _selectGalleryImages,
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
                      onPressed: null,
                      isFullWidth: true,
                    ),
                  )
                : PikaButton(
                    text: '카메라로 촬영',
                    variant: PikaButtonVariant.outline,
                    leadingIcon: Icon(Icons.camera_alt, color: ColorTokens.primary),
                    onPressed: _takeCameraPhoto,
                    isFullWidth: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 갤러리에서 이미지 선택
  Future<void> _selectGalleryImages() async {
    // 바텀시트를 먼저 닫아 UI 블로킹 방지
    Navigator.of(context).pop();
    
    // 이미지 선택을 별도 스케줄링하여 UI 스레드 블로킹 방지
    SchedulerBinding.instance.scheduleFrameCallback((_) async {
      try {
        final List<XFile>? selectedImages = await _picker.pickMultiImage();
        
        if (selectedImages != null && selectedImages.isNotEmpty) {
          // 이미지 처리를 별도 프레임에서 진행
          SchedulerBinding.instance.addPostFrameCallback((_) {
            // XFile을 File로 변환 (간단한 변환)
            final List<File> imageFiles = selectedImages
                .map((xFile) => File(xFile.path))
                .toList();
            
            _noteCreationWorkflow.createNoteWithImages(
              context, 
              imageFiles,
              closeBottomSheet: false // 이미 바텀시트를 닫았으므로 false로 설정
            );
          });
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error picking images: $e');
          // 다음 프레임에 스낵바 표시
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('이미지 선택 중 오류: $e')),
              );
            }
          });
        }
      }
    });
  }
  
  /// 카메라로 사진 촬영
  Future<void> _takeCameraPhoto() async {
    // 바텀시트를 먼저 닫아 UI 블로킹 방지
    Navigator.of(context).pop();
    
    // 카메라 작업을 별도 스케줄링하여 UI 스레드 블로킹 방지
    SchedulerBinding.instance.scheduleFrameCallback((_) async {
      try {
        final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
        
        if (photo != null) {
          // 이미지 처리를 별도 프레임에서 진행
          SchedulerBinding.instance.addPostFrameCallback((_) {
            // XFile을 File로 변환 (간단한 변환)
            final File imageFile = File(photo.path);
            
            _noteCreationWorkflow.createNoteWithImages(
              context, 
              [imageFile],
              closeBottomSheet: false // 이미 바텀시트를 닫았으므로 false로 설정
            );
          });
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error taking photo: $e');
          // 다음 프레임에 스낵바 표시
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('카메라 촬영 중 오류: $e')),
              );
            }
          });
        }
      }
    });
  }
} 