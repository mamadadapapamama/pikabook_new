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

class ImagePickerBottomSheet extends StatefulWidget {
  const ImagePickerBottomSheet({Key? key}) : super(key: key);

  @override
  State<ImagePickerBottomSheet> createState() => _ImagePickerBottomSheetState();
}

class _ImagePickerBottomSheetState extends State<ImagePickerBottomSheet> {
  final ImageService _imageService = ImageService();
  final NoteService _noteService = NoteService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  final ImagePicker _picker = ImagePicker(); // 직접 ImagePicker 인스턴스 사용
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

  /// 갤러리에서 이미지 선택
  Future<void> _selectGalleryImages(BuildContext context) async {
    try {
      debugPrint('갤러리에서 이미지 선택 시작');
      
      // 예외 상황 방지를 위해 try-catch로 감싸기
      try {
        // 먼저 이미지 선택을 시도
        final List<XFile> selectedImages = await _picker.pickMultiImage();
        debugPrint('이미지 선택 작업 완료: ${selectedImages.length}개');
        
        // 선택 완료 후에 바텀 시트 닫기
        if (mounted) Navigator.pop(context);
        
        if (selectedImages.isEmpty) {
          debugPrint('이미지 선택 취소됨');
          return;
        }
        
        // XFile을 File로 변환
        final List<File> imageFiles = selectedImages
            .map((xFile) => File(xFile.path))
            .where((file) => file.existsSync() && file.lengthSync() > 0)
            .toList();
        
        if (imageFiles.isEmpty) {
          debugPrint('변환 후 유효한 이미지 없음');
          return;
        }
        
        // 이미지로 노트 생성
        if (mounted) {
          await _createNoteWithImages(context, imageFiles);
        }
      } catch (innerError) {
        debugPrint('이미지 선택 중 내부 오류: $innerError');
        if (mounted) Navigator.pop(context);
        rethrow; // 외부 catch 블록에서 처리하도록 다시 throw
      }
    } catch (e) {
      debugPrint('갤러리 이미지 선택 중 오류 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 선택 중 오류: $e')),
        );
      }
    }
  }
  
  /// 카메라로 사진 촬영
  Future<void> _takeCameraPhoto(BuildContext context) async {
    try {
      debugPrint('카메라 촬영 시작');
      
      // 예외 상황 방지를 위해 try-catch로 감싸기
      try {
        // 먼저 카메라 촬영 시도
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: 85,
        );
        debugPrint('카메라 촬영 작업 완료: ${photo != null ? '성공' : '취소'}');
        
        // 촬영 완료 후에 바텀 시트 닫기
        if (mounted) Navigator.pop(context);
        
        if (photo == null) {
          debugPrint('카메라 사진 촬영 취소됨');
          return;
        }
        
        // XFile을 File로 변환
        final File imageFile = File(photo.path);
        
        if (!imageFile.existsSync() || imageFile.lengthSync() == 0) {
          debugPrint('카메라로 찍은 이미지가 유효하지 않음');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('이미지를 가져올 수 없습니다. 다시 시도하세요.')),
            );
          }
          return;
        }
        
        // 이미지로 노트 생성
        if (mounted) {
          await _createNoteWithImages(context, [imageFile]);
        }
      } catch (innerError) {
        debugPrint('카메라 촬영 중 내부 오류: $innerError');
        if (mounted) Navigator.pop(context);
        rethrow; // 외부 catch 블록에서 처리하도록 다시 throw
      }
    } catch (e) {
      debugPrint('카메라 촬영 중 오류 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('카메라 촬영 중 오류: $e')),
        );
      }
    }
  }
  
  /// 선택한 이미지로 노트 생성
  Future<void> _createNoteWithImages(BuildContext context, List<File> imageFiles) async {
    if (imageFiles.isEmpty) {
      debugPrint('이미지가 없어 노트 생성 취소');
      return;
    }
    
    debugPrint('노트 생성 시작: ${imageFiles.length}개 이미지');
    String? createdNoteId;
    
    try {
      // 로딩 다이얼로그 표시 - 초기 메시지
      if (mounted) {
        LoadingDialog.show(context, message: '노트 생성 준비 중...');
      }
      
      // 노트 생성 호출
      final result = await _noteService.createNoteWithMultipleImages(
        imageFiles: imageFiles,
        waitForFirstPageProcessing: false, // 기다리지 않고 직접 폴링으로 확인
        progressCallback: (int progress) {
          debugPrint('노트 생성 진행률: $progress%');
          // 진행 상황에 따라 로딩 메시지 업데이트
          if (mounted && progress > 0) {
            // 기존 다이얼로그 닫고 새로운 메시지로 다시 표시
            LoadingDialog.hide();
            Future.microtask(() {
              if (mounted) {
                LoadingDialog.show(context, message: '노트 생성 중... $progress%');
              }
            });
          }
        },
      );
      
      // 노트 생성 성공 확인
      if (result['success'] == true && result['noteId'] != null) {
        createdNoteId = result['noteId'] as String;
        debugPrint('노트 ID 생성 성공: $createdNoteId');
        
        if (mounted) {
          // 로딩 메시지 업데이트
          LoadingDialog.hide();
          Future.microtask(() {
            if (mounted) {
              LoadingDialog.show(context, message: '첫 페이지 처리 중...');
            }
          });
        }
        
        // 첫 번째 페이지 처리 완료 확인 (최대 10초)
        bool firstPageProcessed = false;
        int attempts = 0;
        const maxAttempts = 20; // 10초 (0.5초 간격으로 20번)
        
        while (!firstPageProcessed && attempts < maxAttempts && mounted) {
          attempts++;
          
          try {
            final statusResult = await _noteService.checkFirstPageProcessingStatus(createdNoteId);
            firstPageProcessed = statusResult['processed'] == true;
            
            if (firstPageProcessed) {
              debugPrint('첫 번째 페이지 처리 완료: $createdNoteId (시도: $attempts)');
              break;
            }
            
            // 진행 메시지 업데이트 (5번마다)
            if (attempts % 5 == 0 && mounted) {
              LoadingDialog.hide();
              // microtask를 사용하여 현재 실행 스택이 완료된 후 UI 업데이트
              Future.microtask(() {
                if (mounted) {
                  LoadingDialog.show(context, message: '첫 페이지 처리 중... (${attempts / 2}초)');
                }
              });
            }
            
            // 0.5초 대기
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            debugPrint('첫 번째 페이지 처리 상태 확인 중 오류: $e');
            break; // 오류 발생 시 루프 종료
          }
        }
      } else {
        // 노트 생성 실패
        debugPrint('노트 생성 결과 실패: ${result['message']}');
        
        // 로딩 다이얼로그 숨기기
        LoadingDialog.hide();
        
        // 실패 메시지 표시
        final String errorMessage = result['message'] as String? ?? '노트 생성에 실패했습니다.';
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('노트 생성 실패: $errorMessage')),
          );
        }
        return; // 노트 생성 실패 시 여기서 종료
      }
    } catch (e) {
      // 로딩 다이얼로그 숨기기
      LoadingDialog.hide();
      
      debugPrint('노트 생성 중 예외 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 생성 중 오류가 발생했습니다')),
        );
      }
      return; // 오류 발생 시 여기서 종료
    }
    
    // 로딩 다이얼로그 숨기기 - 반드시 마지막에 한번 더 확인
    LoadingDialog.hide();
    
    // 정상적으로 노트가 생성되었으면 노트 상세 화면으로 이동
    if (createdNoteId != null && createdNoteId.isNotEmpty && mounted) {
      debugPrint('노트 생성 후 상세 화면으로 이동: $createdNoteId');
      
      // nullability 오류를 해결하기 위해 로컬 변수에 할당
      final String noteId = createdNoteId;
      
      // 이전 화면들을 모두 대체하여 사용자가 뒤로가기 시 홈 화면으로 돌아가도록 함
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => NoteDetailScreen(noteId: noteId),
        ),
        (route) => route.isFirst, // 첫 번째 루트(홈 화면)만 남김
      );
    }
  }
} 