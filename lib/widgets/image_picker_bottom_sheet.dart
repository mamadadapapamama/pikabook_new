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
      
      // 바텀 시트를 먼저 닫지 않도록 변경
      
      // 예외 상황 방지를 위해 try-catch로 감싸기
      try {
        // 먼저 이미지 선택을 시도
        final List<XFile> selectedImages = await _picker.pickMultiImage();
        debugPrint('이미지 선택 작업 완료: ${selectedImages.length}개');
        
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
        
        // 이미지 선택 및 변환 완료 후에 바텀 시트 닫지 않음 (노트 생성 메소드에서 처리)
        
        // 이미지로 노트 생성 (_createNoteWithImages에서 바텀 시트 닫기)
        if (mounted) {
          await _createNoteWithImages(context, imageFiles);
        }
      } catch (innerError) {
        debugPrint('이미지 선택 중 내부 오류: $innerError');
        if (mounted) {
          // 오류 발생 시에만 바텀 시트 닫기
          Navigator.pop(context);
        }
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
      
      // 바텀 시트를 먼저 닫지 않도록 변경
      
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
        
        // 이미지 촬영 완료 후에 바텀 시트 닫지 않음 (노트 생성 메소드에서 처리)
        
        // 이미지로 노트 생성
        if (mounted) {
          await _createNoteWithImages(context, [imageFile]);
        }
      } catch (innerError) {
        debugPrint('카메라 촬영 중 내부 오류: $innerError');
        if (mounted) {
          // 오류 발생 시에만 바텀 시트 닫기
          Navigator.pop(context);
        }
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
    
    // 화면 전환을 위해 부모 컨텍스트 미리 저장
    final BuildContext parentContext = Navigator.of(context).context;
    
    // 바텀 시트를 즉시 닫기
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    
    // 바텀 시트가 완전히 닫히길 기다린 후 로딩 다이얼로그 표시
    await Future.delayed(const Duration(milliseconds: 100));
    
    // 로딩 다이얼로그 표시
    if (parentContext.mounted) {
      LoadingDialog.show(parentContext, message: '노트 생성 준비 중...');
    }
    
    String? createdNoteId;
    
    try {
      // 노트 생성 호출
      final result = await _noteService.createNoteWithMultipleImages(
        imageFiles: imageFiles,
        waitForFirstPageProcessing: false,
        progressCallback: (int progress) {
          debugPrint('노트 생성 진행률: $progress%');
        },
      );
      
      // 노트 생성 성공 확인
      if (result['success'] == true && result['noteId'] != null) {
        createdNoteId = result['noteId'] as String;
        debugPrint('노트 ID 생성 성공: $createdNoteId');
        
        // 로딩 메시지 업데이트 - Future.microtask 사용
        Future.microtask(() {
          LoadingDialog.updateMessage('스마트 노트를 만들고 있어요.\n잠시만 기다려 주세요... (0/10초)');
        });
        
        // 변수에 보관할 노트 ID 복사 (중간에 null이 되지 않도록)
        final String noteId = createdNoteId;
        
        // 첫 번째 페이지 처리 완료 또는 타임아웃 대기 (최대 10초)
        bool firstPageProcessed = false;
        int attempts = 0;
        const maxAttempts = 20; // 10초 (0.5초 간격으로 20번)
        
        while (!firstPageProcessed && attempts < maxAttempts) {
          attempts++;
          
          try {
            final statusResult = await _noteService.checkFirstPageProcessingStatus(noteId);
            firstPageProcessed = statusResult['processed'] == true;
            
            if (firstPageProcessed) {
              debugPrint('첫 번째 페이지 처리 완료: $noteId (시도: $attempts)');
              break;
            }
            
            // 진행 메시지 업데이트 - Future.microtask 사용
            final progressSeconds = (attempts / 2).toStringAsFixed(1);
            final message = '첫 페이지 처리 중... ($progressSeconds/10초)';
            Future.microtask(() {
              LoadingDialog.updateMessage(message);
            });
            debugPrint('로딩 메시지 업데이트: $message');
            
            // 0.5초 대기
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            debugPrint('첫 번째 페이지 처리 상태 확인 중 오류: $e');
            // 오류가 발생해도 계속 진행 (break 제거)
          }
        }
        
        // 타임아웃이 발생해도 노트 상세 화면으로 이동
        debugPrint('노트 페이지 처리 완료 여부: ${firstPageProcessed ? '완료' : '처리 중'}, 시도 횟수: $attempts');
        
        // 로딩 다이얼로그 숨기기 - 안정적인 실행을 위해 try-catch로 감싸기
        try {
          LoadingDialog.hide();
          debugPrint('로딩 다이얼로그 숨김 완료');
        } catch (e) {
          debugPrint('로딩 다이얼로그 숨기기 오류: $e');
        }
        
        // 약간의 딜레이 후 화면 전환 시도
        await Future.delayed(const Duration(milliseconds: 300));
        
        // 부모 컨텍스트를 사용하여 노트 상세 화면으로 이동
        if (parentContext.mounted) {
          debugPrint('부모 컨텍스트를 사용하여 노트 상세 화면으로 이동 시도');
          
          Navigator.of(parentContext).push(
            MaterialPageRoute(
              builder: (context) => NoteDetailScreen(
                noteId: noteId,
                isProcessingBackground: !firstPageProcessed,
                totalImageCount: imageFiles.length,
              ),
            ),
          ).then((_) {
            debugPrint('노트 상세 화면에서 돌아옴');
          }).catchError((error) {
            debugPrint('노트 상세 화면 이동 중 오류: $error');
            
            // 오류 발생 시 스낵바로 알림
            if (parentContext.mounted) {
              ScaffoldMessenger.of(parentContext).showSnackBar(
                SnackBar(
                  content: Text('노트가 생성되었지만 화면 이동에 실패했습니다.'),
                  action: SnackBarAction(
                    label: '확인',
                    onPressed: () {
                      // 다시 시도 (한 번 더)
                      if (parentContext.mounted) {
                        Navigator.of(parentContext).push(
                          MaterialPageRoute(
                            builder: (context) => NoteDetailScreen(
                              noteId: noteId,
                              isProcessingBackground: !firstPageProcessed,
                              totalImageCount: imageFiles.length,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          });
        } else {
          debugPrint('부모 컨텍스트도 유효하지 않아 노트 상세 화면으로 이동할 수 없습니다');
        }
      } else {
        // 노트 생성 실패
        debugPrint('노트 생성 결과 실패: ${result['message']}');
        
        // 로딩 다이얼로그 숨기기 - 안정적인 실행을 위해 try-catch로 감싸기
        try {
          LoadingDialog.hide();
        } catch (e) {
          debugPrint('로딩 다이얼로그 숨기기 오류: $e');
        }
        
        // 실패 메시지 표시
        final String errorMessage = result['message'] as String? ?? '노트 생성에 실패했습니다.';
        
        if (parentContext.mounted) {
          ScaffoldMessenger.of(parentContext).showSnackBar(
            SnackBar(content: Text('노트 생성 실패: $errorMessage')),
          );
        }
      }
    } catch (e) {
      // 에러 발생 시 로딩 다이얼로그 숨기기 - 안정적인 실행을 위해 try-catch로 감싸기
      try {
        LoadingDialog.hide();
      } catch (innerError) {
        debugPrint('로딩 다이얼로그 숨기기 오류: $innerError');
      }
      
      debugPrint('노트 생성 중 예외 발생: $e');
      if (parentContext.mounted) {
        ScaffoldMessenger.of(parentContext).showSnackBar(
          SnackBar(content: Text('노트 생성 중 오류가 발생했습니다')),
        );
      }
    }
  }
} 