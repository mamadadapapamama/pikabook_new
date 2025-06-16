import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import 'pika_button.dart';
import 'package:image_picker/image_picker.dart';
import '../../features/note/managers/note_creation_ui_manager.dart';
import '../../core/services/media/image_service.dart';
import 'loading_dialog_experience.dart';

class ImagePickerBottomSheet extends StatefulWidget {
  const ImagePickerBottomSheet({Key? key}) : super(key: key);

  @override
  State<ImagePickerBottomSheet> createState() => _ImagePickerBottomSheetState();
}

class _ImagePickerBottomSheetState extends State<ImagePickerBottomSheet> {
  final NoteCreationUIManager _noteCreationUIManager = NoteCreationUIManager();
  final ImagePicker _picker = ImagePicker();
  final ImageService _imageService = ImageService();
  
  bool _isProcessing = false;

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
            // 상단 헤더
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
            
            // 갤러리 버튼
            PikaButton(
              text: '갤러리에서 선택',
              variant: PikaButtonVariant.outline,
              leadingIcon: Icon(Icons.photo_library, color: ColorTokens.primary),
              onPressed: _isProcessing ? null : _selectGalleryImages,
              isFullWidth: true,
            ),
            
            const SizedBox(height: 16),
            
            // 카메라 버튼
            PikaButton(
              text: '카메라로 촬영',
              variant: PikaButtonVariant.outline,
              leadingIcon: Icon(Icons.camera_alt, color: ColorTokens.primary),
              onPressed: _isProcessing ? null : _takeCameraPhoto,
              isFullWidth: true,
            ),
          ],
        ),
      ),
    );
  }

  /// 갤러리에서 이미지 선택
  Future<void> _selectGalleryImages() async {
    if (_isProcessing) return;
    
    setState(() => _isProcessing = true);
    
    try {
      print('📱 갤러리 이미지 선택 시작');
      
      final List<File> imageFiles = await _imageService.pickMultipleImages();
      
      if (imageFiles.isEmpty) {
        print('📱 갤러리 이미지 선택 취소됨');
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
        return;
      }
      
      print('📱 갤러리 이미지 선택 성공: ${imageFiles.length}개');
      await _processSelectedImages(imageFiles);
      
    } catch (e) {
      print('📱 갤러리 이미지 선택 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지를 선택할 수 없습니다. 다시 시도해주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  
  /// 카메라로 사진 촬영
  Future<void> _takeCameraPhoto() async {
    if (_isProcessing) return;
    
    setState(() => _isProcessing = true);
    
    try {
      print('📷 카메라 촬영 시작');
      
      final File? imageFile = await _imageService.pickImage(source: ImageSource.camera);
      
      if (imageFile == null) {
        print('📷 카메라 촬영 취소됨');
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
        return;
      }
      
      if (!await imageFile.exists() || await imageFile.length() == 0) {
        throw Exception('촬영된 이미지 파일이 유효하지 않습니다.');
      }
      
      print('📷 카메라 촬영 성공: ${imageFile.path}');
      await _processSelectedImages([imageFile]);
      
    } catch (e) {
      print('📷 카메라 촬영 오류: $e');
      
      String errorMessage;
      if (Platform.isIOS && e.toString().contains('simulator')) {
        errorMessage = 'iOS 시뮬레이터에서는 카메라를 사용할 수 없습니다. 실제 기기에서 테스트해주세요.';
      } else {
        errorMessage = '카메라를 사용할 수 없습니다. 갤러리에서 이미지를 선택해주세요.';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  
  /// 선택된 이미지들을 처리하는 공통 메서드
  Future<void> _processSelectedImages(List<File> imageFiles) async {
    if (!mounted) return;
    
    try {
      // 바텀 시트 닫기
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      // 노트 생성 처리
      await _noteCreationUIManager.createNoteWithImages(
        context, 
        imageFiles,
        closeBottomSheet: false,
        showLoadingDialog: true
      );
      
    } catch (e) {
      print('이미지 처리 중 오류: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kDebugMode 
              ? '노트 생성 중 오류가 발생했습니다: $e' 
              : '노트 생성 중 오류가 발생했습니다. 다시 시도해주세요.'
            ),
          ),
        );
      }
    }
  }
} 