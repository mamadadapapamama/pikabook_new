import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';  // min 함수를 위한 import 추가
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import 'pika_button.dart';
import 'package:image_picker/image_picker.dart';
import '../../features/note/managers/note_creation_ui_manager.dart';
import '../../core/services/media/image_service.dart';
import 'loading_dialog_experience.dart';
import '../../core/services/permissions/permission_service.dart';

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
  
  // 이미지 처리 중인지 추적하는 변수
  bool _isProcessing = false;
  bool _isCancelled = false; // 취소 상태 추적 변수 추가
  
  @override
  void initState() {
    super.initState();
  }
  
  @override
  void dispose() {
    // dispose 될 때 처리 상태 초기화
    _isProcessing = false;
    _isCancelled = false;
    super.dispose();
  }
  
  // 상태 초기화를 위한 별도 메서드 (일관된 처리를 위함)
  void _resetProcessingState() {
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _isCancelled = false;
      });
    } else {
      _isProcessing = false;
      _isCancelled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () {
        // 뒤로가기 시 취소 상태로 설정
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _isCancelled = true;
          });
        } else {
          _isProcessing = false;
          _isCancelled = true;
        }
        return Future.value(true);
      },
      child: Container(
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
                    onTap: () {
                      // X 버튼 클릭시 취소 상태로 설정 후 닫기
                      if (mounted) {
                        setState(() {
                          _isProcessing = false;
                          _isCancelled = true;
                        });
                      } else {
                        _isProcessing = false;
                        _isCancelled = true;
                      }
                      Navigator.pop(context);
                    },
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
                    onPressed: _selectGalleryImages,
                    isFullWidth: true,
                  ),
                
                const SizedBox(height: 16),
                
                PikaButton(
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
      ),
    );
  }

  /// 갤러리에서 이미지 선택 (PermissionService 사용)
  Future<void> _selectGalleryImages() async {
    // 이미 처리 중이거나 취소된 경우 중복 호출 방지
    if (_isProcessing || _isCancelled) {
      if (kDebugMode) {
        print('갤러리 이미지 선택 중복 호출 방지: processing=$_isProcessing, cancelled=$_isCancelled');
      }
      return;
    }
    
    // 처리 중 상태로 설정
    setState(() {
      _isProcessing = true;
      _isCancelled = false;
    });
    
    try {
      // 갤러리 권한 확인 및 요청
      final hasPermission = await _permissionService.requestGalleryPermission(context);
      if (!hasPermission) {
        _resetProcessingState();
        return;
      }
      
      if (kDebugMode) {
        print('📱 갤러리 이미지 선택 시작 (권한 확인 완료)');
      }
      
      // 기존 ImageService를 통한 갤러리 이미지 선택
      final List<File> imageFiles = await _imageService.pickMultipleImages();
        
      // 이미지 선택이 취소되었거나 이미지가 없는 경우
      if (imageFiles.isEmpty) {
        if (kDebugMode) {
          print('📱 갤러리 이미지 선택 취소됨');
        }
        _resetProcessingState();
        
        // 취소 시 바텀시트 닫기
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
        return;
      }
      
      if (kDebugMode) {
        print('📱 갤러리 이미지 선택 성공: ${imageFiles.length}개');
      }
      
      // 성공적으로 선택된 경우 노트 생성 진행
      await _processSelectedImages(imageFiles);
      
    } catch (e) {
      if (kDebugMode) {
        print('📱 갤러리 이미지 선택 오류: $e');
      }
      
      _resetProcessingState();
      
      // 오류 메시지 표시
      String errorMessage;
      if (e.toString().contains('permission') || e.toString().contains('denied')) {
        errorMessage = '갤러리 접근 권한이 필요합니다. 설정에서 사진 권한을 허용해주세요.';
      } else {
        errorMessage = '이미지를 선택할 수 없습니다. 다시 시도해주세요.';
      }
      
      if (mounted) {
        _showSingleAlert('갤러리 오류', errorMessage);
      }
    }
  }
  
  /// 카메라로 사진 촬영 (PermissionService 사용)
  Future<void> _takeCameraPhoto() async {
    // 이미 처리 중이거나 취소된 경우 중복 호출 방지
    if (_isProcessing || _isCancelled) {
      if (kDebugMode) {
        print('카메라 촬영 중복 호출 방지: processing=$_isProcessing, cancelled=$_isCancelled');
      }
      return;
    }
    
    // 처리 중 상태로 설정
    setState(() {
      _isProcessing = true;
      _isCancelled = false;
    });
    
    try {
      // 카메라 권한 확인 및 요청
      final hasPermission = await _permissionService.requestCameraPermission(context);
      if (!hasPermission) {
        _resetProcessingState();
        return;
      }
      
      if (kDebugMode) {
        print('📷 카메라 촬영 시작 (권한 확인 완료)');
      }
      
      // 기존 ImageService를 통한 카메라 촬영
      final File? imageFile = await _imageService.pickImage(source: ImageSource.camera);
      
      if (imageFile == null) {
        // 사용자가 취소한 경우
        if (kDebugMode) {
          print('📷 카메라 촬영 취소됨');
        }
        _resetProcessingState();
        
        // 취소 시 바텀시트 닫기
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
        return;
      }
      
      // 파일 유효성 검사
      if (!await imageFile.exists() || await imageFile.length() == 0) {
        throw Exception('촬영된 이미지 파일이 유효하지 않습니다.');
      }
      
      if (kDebugMode) {
        print('📷 카메라 촬영 성공: ${imageFile.path}');
      }
      
      // 성공적으로 촬영된 경우 노트 생성 진행
      await _processSelectedImages([imageFile]);
      
    } catch (e) {
      if (kDebugMode) {
        print('📷 카메라 촬영 오류: $e');
      }
      
      _resetProcessingState();
      
      // 오류 메시지 표시
      String errorMessage;
      if (e.toString().contains('permission') || e.toString().contains('denied')) {
        errorMessage = '카메라 권한이 필요합니다. 설정에서 카메라 권한을 허용해주세요.';
      } else if (Platform.isIOS && e.toString().contains('simulator')) {
        errorMessage = 'iOS 시뮬레이터에서는 카메라를 사용할 수 없습니다. 실제 기기에서 테스트해주세요.';
      } else {
        errorMessage = '카메라를 사용할 수 없습니다. 갤러리에서 이미지를 선택해주세요.';
      }
      
      if (mounted) {
        _showSingleAlert('카메라 오류', errorMessage);
      }
    }
  }
  
  /// 선택된 이미지들을 처리하는 공통 메서드 (단순화)
  Future<void> _processSelectedImages(List<File> imageFiles) async {
    if (!mounted) return;
    
    try {
      // 바텀 시트 닫기
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
        
        // 안정성을 위해 약간의 딜레이 추가
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      // NoteCreationUIManager가 로딩 다이얼로그와 모든 처리를 담당
      await _noteCreationUIManager.createNoteWithImages(
        context, 
        imageFiles,
        closeBottomSheet: false, // 이미 닫았으므로 false
        showLoadingDialog: true  // NoteCreationUIManager가 로딩 처리
      );
      
    } catch (e) {
      if (kDebugMode) {
        print('이미지 처리 중 오류: $e');
      }
      
      if (mounted) {
        _showSingleAlert(
          '처리 오류',
          kDebugMode 
            ? '노트 생성 중 오류가 발생했습니다: $e' 
            : '노트 생성 중 오류가 발생했습니다. 다시 시도해주세요.'
        );
      }
    } finally {
      // 처리 완료 후 상태 초기화
      _resetProcessingState();
    }
  }
  
  // 한 번만 표시되는 얼럿 메시지 (중복 방지)
  void _showSingleAlert(String title, String message, {BuildContext? context}) {
    final ctx = context ?? this.context;
    
    // 이미 표시된 메시지 닫기
    Navigator.of(ctx, rootNavigator: true).popUntil((route) {
      return route.isFirst || !(route is DialogRoute);
    });
    
    // 새 얼럿 표시
    showDialog(
      context: ctx,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('확인'),
          ),
        ],
      ),
        );
  }
} 