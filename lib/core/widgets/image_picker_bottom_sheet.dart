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
import '../../core/services/permissions/permission_service.dart';
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
  final PermissionService _permissionService = PermissionService();
  
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _checkCurrentPermissions();
    }
  }

  /// 디버그용: 현재 권한 상태 확인
  Future<void> _checkCurrentPermissions() async {
    final status = await _permissionService.checkPermissionStatus();
    print('🔍 바텀시트 초기화 시 권한 상태: $status');
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
      
      // image_picker가 자체적으로 권한을 처리하도록 함
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
          SnackBar(
          content: Text('이미지를 선택할 수 없습니다. 다시 시도해주세요.'),
          duration: const Duration(seconds: 2),
        ),
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
      
      // 카메라 촬영 전 컨텍스트 저장
      final BuildContext savedContext = context;
      
      // image_picker가 자체적으로 권한을 처리하도록 함
      final File? imageFile = await _imageService.pickImage(source: ImageSource.camera);
      
      // 카메라 촬영 후 위젯 상태 재확인 (중요!)
      if (!mounted) {
        print('📷 카메라 촬영 후 위젯이 더 이상 마운트되지 않음');
        return;
      }
      
      if (imageFile == null) {
        print('📷 카메라 촬영 취소됨');
        // 안전한 네비게이션 처리
        _safeNavigatorPop(savedContext);
        return;
      }
      
      // 파일 유효성 검증 강화
      if (!await imageFile.exists()) {
        throw Exception('촬영된 이미지 파일을 찾을 수 없습니다.');
      }
      
      final fileSize = await imageFile.length();
      if (fileSize == 0) {
        throw Exception('촬영된 이미지 파일이 비어있습니다.');
      }
      
      if (fileSize > 50 * 1024 * 1024) { // 50MB 제한
        throw Exception('이미지 파일이 너무 큽니다. (최대 50MB)');
      }
      
      print('📷 카메라 촬영 성공: ${imageFile.path} (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB)');
      
      // 위젯 상태 재확인 후 처리
      if (mounted) {
        // 잠시 대기하여 위젯 트리 안정화
        await Future.delayed(const Duration(milliseconds: 200));
        
        if (mounted) {
          await _processSelectedImages([imageFile]);
        }
      }
      
    } catch (e) {
      print('📷 카메라 촬영 오류: $e');
      
      String errorMessage;
      if (Platform.isIOS && e.toString().contains('simulator')) {
        errorMessage = 'iOS 시뮬레이터에서는 카메라를 사용할 수 없습니다. 실제 기기에서 테스트해주세요.';
      } else if (e.toString().contains('권한')) {
        errorMessage = '카메라 권한이 필요합니다. 설정에서 권한을 허용해주세요.';
      } else if (e.toString().contains('파일')) {
        errorMessage = e.toString();
      } else {
        errorMessage = '카메라를 사용할 수 없습니다. 갤러리에서 이미지를 선택해주세요.';
      }
      
      // 안전한 에러 메시지 표시
      _safeShowErrorMessage(errorMessage);
      
    } finally {
      // 안전한 상태 업데이트
      _safeSetState(() => _isProcessing = false);
    }
  }
  
  /// 안전한 네비게이터 팝
  void _safeNavigatorPop(BuildContext savedContext) {
    try {
      if (mounted && Navigator.canPop(savedContext)) {
        Navigator.of(savedContext).pop();
      }
    } catch (e) {
      print('⚠️ 네비게이터 팝 실패: $e');
    }
  }
  
  /// 안전한 에러 메시지 표시
  void _safeShowErrorMessage(String message) {
    if (!mounted) return;
    
    // 위젯 트리 안정화를 위한 대기
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red[600],
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } catch (e) {
          print('⚠️ 에러 메시지 표시 실패: $e');
        }
      }
    });
  }
  
  /// 안전한 setState
  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      try {
        setState(fn);
      } catch (e) {
        print('⚠️ setState 실패: $e');
      }
    }
  }
  
  /// 선택된 이미지들을 처리하는 공통 메서드
  Future<void> _processSelectedImages(List<File> imageFiles) async {
    if (!mounted) return;
    
    try {
      print('📱 이미지 처리 시작: ${imageFiles.length}개');
      
      // 컨텍스트를 미리 저장
      final BuildContext savedContext = context;
      
      // 바텀 시트 닫기 (빠르게)
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      // 최소한의 대기만 (300ms → 100ms)
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 노트 생성 처리 (저장된 컨텍스트 사용)
      await _noteCreationUIManager.createNoteWithImages(
        savedContext, 
        imageFiles,
        closeBottomSheet: false, // 이미 닫았으므로 false
        showLoadingDialog: true
      );
      
    } catch (e) {
      print('❌ 이미지 처리 중 오류: $e');
      
      // 안전한 에러 메시지 표시
      _safeShowErrorMessage(kDebugMode 
        ? '노트 생성 중 오류가 발생했습니다: $e' 
        : '노트 생성 중 오류가 발생했습니다. 다시 시도해주세요.'
      );
    } finally {
      // 상태 정리
      _safeSetState(() => _isProcessing = false);
    }
  }
} 