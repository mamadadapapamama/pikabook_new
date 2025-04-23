import 'package:flutter/material.dart';
import 'dart:io';
import '../core/services/media/image_service.dart';
import '../core/services/content/note_service.dart';
import '../features/note_detail/note_detail_screen_mvvm.dart';
import '../core/theme/tokens/color_tokens.dart';
import '../core/theme/tokens/typography_tokens.dart';
import '../core/widgets/pika_button.dart';
import 'package:image_picker/image_picker.dart';
import '../core/services/common/usage_limit_service.dart';
import 'dart:async';
import '../core/widgets/loading_dialog_experience.dart';
import '../core/models/note.dart';

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
    
    final BuildContext parentContext = Navigator.of(context).context;
    final BuildContext appContext = Navigator.of(parentContext, rootNavigator: true).context;
    
    // 바텀 시트 닫기
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
      debugPrint('바텀 시트 닫힘');
    }
    
    // PikabookLoader 사용 - 기존 LoadingDialog보다 안정적
    if (appContext.mounted) {
      debugPrint('로딩 다이얼로그 표시 시작');
      await NoteCreationLoader.show(
        appContext, 
        message: '스마트 노트를 만들고 있어요\n잠시만 기다려 주세요!'
      );
      debugPrint('로딩 다이얼로그 표시 완료');
    } else {
      debugPrint('앱 컨텍스트가 유효하지 않아 로딩 다이얼로그를 표시할 수 없음');
    }
    
    String? createdNoteId;
    
    try {
      debugPrint('노트 생성 시작: ${imageFiles.length}개 이미지');
      // 노트 생성 (백그라운드 처리 위임)
      final result = await _noteService.createNoteWithMultipleImages(
        imageFiles: imageFiles,
        waitForFirstPageProcessing: false,
      );
      debugPrint('노트 생성 완료: $result');
      
      // 성공 여부 체크
      final bool isSuccess = result['success'] == true;
      createdNoteId = result['noteId'] as String?;
      
      // 로더 숨기기
      try {
        if (appContext.mounted) {
          debugPrint('로딩 다이얼로그 숨김 시작');
          NoteCreationLoader.hide(appContext);
          debugPrint('로딩 다이얼로그 숨김 완료');
        }
      } catch (e) {
        debugPrint('로딩 다이얼로그 숨김 중 오류: $e');
      }
      
      // 약간의 딜레이 추가 (화면 전환 안정성 개선)
      await Future.delayed(const Duration(milliseconds: 300));
      
      // 노트 생성 성공 시 상세 화면으로 이동
      if (isSuccess && createdNoteId != null) {
        debugPrint('노트 ID: $createdNoteId - 상세 화면으로 이동 시도');
        
        // 약간의 딜레이 추가 (화면 전환 안정성 개선)
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (appContext.mounted) {
          try {
            debugPrint('노트 상세 화면으로 이동 시작');
            
            // 임시 Note 객체 생성
            final tempNote = Note(
              id: createdNoteId,
              originalText: '새 노트',
              translatedText: '',
              extractedText: '',
            );
            
            Navigator.of(appContext).push(
              NoteDetailScreenMVVM.route(
                note: tempNote,
                isProcessingBackground: true,
                totalImageCount: imageFiles.length,
              ),
            );
            
            debugPrint('노트 상세 화면으로 이동 완료');
          } catch (navError) {
            debugPrint('노트 상세 화면 이동 중 오류: $navError');
            
            // 약간의 딜레이 후 다시 시도
            await Future.delayed(const Duration(milliseconds: 500));
            
            // 이동 실패 시 스낵바 표시
            if (appContext.mounted) {
              ScaffoldMessenger.of(appContext).showSnackBar(
                SnackBar(
                  content: Text('노트가 생성되었지만 화면 이동에 실패했습니다.'),
                  action: SnackBarAction(
                    label: '확인',
                    onPressed: () {
                      // 다시 시도 - 홈으로 돌아간 후 이동
                      if (appContext.mounted && createdNoteId != null) {
                        // 임시 Note 객체 생성
                        final tempNote = Note(
                          id: createdNoteId,
                          originalText: '새 노트',
                          translatedText: '',
                          extractedText: '',
                        );
                        
                        // 홈으로 돌아가기
                        Navigator.of(appContext).popUntil((route) => route.isFirst);
                        
                        // 약간의 딜레이 후 노트 상세 화면으로 이동
                        Future.delayed(const Duration(milliseconds: 300), () {
                          if (appContext.mounted) {
                            Navigator.of(appContext).push(
                              NoteDetailScreenMVVM.route(
                                note: tempNote,
                                isProcessingBackground: true,
                                totalImageCount: imageFiles.length,
                              ),
                            );
                          }
                        });
                      }
                    },
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }
        } else {
          debugPrint('앱 컨텍스트가 유효하지 않아 노트 상세 화면으로 이동할 수 없음');
        }
      } else {
        // 실패 시 메시지 표시
        final errorMessage = result['message'] as String? ?? '노트 생성에 실패했습니다';
        debugPrint('노트 생성 실패: $errorMessage');
        if (appContext.mounted) {
          ScaffoldMessenger.of(appContext).showSnackBar(
            SnackBar(content: Text(errorMessage)),
          );
        }
      }
    } catch (e) {
      debugPrint('노트 생성 중 예외 발생: $e');
      // 에러 처리
      try {
        if (appContext.mounted) {
          NoteCreationLoader.hide(appContext);
        }
      } catch (loaderError) {
        debugPrint('로더 숨김 중 오류: $loaderError');
      }
      
      if (appContext.mounted) {
        ScaffoldMessenger.of(appContext).showSnackBar(
          SnackBar(content: Text('노트 생성 중 오류가 발생했습니다')),
        );
      }
    } finally {
      // 성공적으로 노트가 생성되었지만 화면 이동에 실패한 경우 스낵바 표시
      if (createdNoteId != null && appContext.mounted) {
        // Navigator에 NoteDetailScreen이 이미 있는지 확인
        bool alreadyNavigated = false;
        Navigator.of(appContext).popUntil((route) {
          if (route.settings.name == '/note_detail') {
            alreadyNavigated = true;
          }
          return true;
        });
        
        if (!alreadyNavigated) {
          debugPrint('노트는 생성되었지만 화면 이동이 확인되지 않음: $createdNoteId');
          ScaffoldMessenger.of(appContext).showSnackBar(
            SnackBar(
              content: Text('노트가 생성되었습니다. 노트 목록에서 확인하세요.'),
              action: SnackBarAction(
                label: '상세보기',
                onPressed: () {
                  if (appContext.mounted) {
                    // 임시 Note 객체 생성
                    final tempNote = Note(
                      id: createdNoteId,
                      originalText: '새 노트',
                      translatedText: '',
                      extractedText: '',
                    );
                    
                    Navigator.of(appContext).push(
                      NoteDetailScreenMVVM.route(
                        note: tempNote,
                        isProcessingBackground: true,
                        totalImageCount: imageFiles.length,
                      ),
                    );
                  }
                },
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }
} 