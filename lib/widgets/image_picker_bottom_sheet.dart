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
    
    // 생성된 노트 ID 저장용 변수
    String? createdNoteId;
    bool creationSucceeded = false;
    
    // 타이머 변수 생성 - 나중에 취소할 수 있도록 보관
    Timer? loadingTimer;
    
    try {
      // 노트 생성 시작: 이미지 개수 저장
      final int imageCount = images.length;
      
      // 여러 이미지로 노트 생성 (먼저 노트부터 생성)
      final result = await _noteService.createNoteWithMultipleImages(
        imageFiles: images,
        title: null, // 자동 타이틀 생성을 위해 null 전달
        silentProgress: true, // 진행 상황 업데이트 무시
        waitForFirstPageProcessing: false, // 첫 페이지 처리 완료까지 대기하지 않고 바로 결과 반환
      );

      // 결과 저장
      final bool success = result['success'] == true;
      createdNoteId = result['noteId'] as String?;
      final bool isProcessingBackground = result['isProcessingBackground'] ?? false;
      final String message = result['message'] ?? '노트 생성에 실패했습니다.';
      
      // 성공 여부 저장
      creationSucceeded = success && createdNoteId != null;
      
      // 로딩 다이얼로그 표시
      if (context.mounted) {
        // 로딩 다이얼로그 표시 (기본 메시지 사용)
        LoadingDialog.show(context);
        isLoadingDialogShowing = true;
        
        // 무조건 닫히게 하는 강제 타이머 설정 (10초 후 무조건 닫히고 페이지 이동)
        loadingTimer = Timer(Duration(seconds: 10), () {
          if (isLoadingDialogShowing && context.mounted) {
            isLoadingDialogShowing = false;
            
            // 노트 생성에 성공했으면 노트 페이지로 이동
            if (creationSucceeded && context.mounted) {
              // 먼저 페이지 이동 수행 후 다이얼로그 닫기
              _navigateToNoteDetail(context, createdNoteId!, isProcessingBackground);
              
              // 페이지 이동 후 적절한 지연을 두고 로딩 다이얼로그 닫기
              Future.delayed(Duration(milliseconds: 100), () {
                if (context.mounted) {
                  LoadingDialog.hide(context);
                }
              });
            } else {
              // 실패한 경우 다이얼로그 닫기
              if (context.mounted) {
                LoadingDialog.hide(context);
              }
            }
          }
        });
      }
      
      // 첫 페이지 처리 완료 대기 (최대 8초)
      if (creationSucceeded) {
        bool firstPageProcessed = false;
        int waitCount = 0;
        const int maxWaitSeconds = 8;
        
        while (!firstPageProcessed && waitCount < maxWaitSeconds && context.mounted && isLoadingDialogShowing) {
          try {
            // 첫 페이지 처리 상태 확인
            final pageStatus = await _noteService.checkFirstPageProcessingStatus(createdNoteId!);
            firstPageProcessed = pageStatus['processed'] == true;
            
            if (firstPageProcessed) {
              break;
            }
          } catch (e) {
            // 에러 무시
          }
          
          // 1초 대기 후 다시 확인
          await Future.delayed(Duration(seconds: 1));
          waitCount++;
        }
      }

      // 첫 페이지 처리 완료 또는 대기 시간 초과 후, 타이머가 작동 중이면 취소
      loadingTimer?.cancel();
      
      // 결과에 따라 다음 화면으로 이동
      if (creationSucceeded && context.mounted && isLoadingDialogShowing) {
        isLoadingDialogShowing = false;
        
        // 페이지 이동 먼저 수행
        _navigateToNoteDetail(context, createdNoteId!, isProcessingBackground);
        
        // 페이지 이동 후 적절한 지연을 두고 로딩 다이얼로그 닫기
        Future.delayed(Duration(milliseconds: 100), () {
          if (context.mounted) {
            LoadingDialog.hide(context);
          }
        });
      } else if (context.mounted && isLoadingDialogShowing) {
        // 실패한 경우 다이얼로그 닫기 후 오류 메시지 표시
        isLoadingDialogShowing = false;
        LoadingDialog.hide(context);
        
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
      }
    } catch (e) {
      // 오류 발생 시 타이머 취소
      loadingTimer?.cancel();
      
      // 노트 생성에 성공했으면 오류가 있어도 노트 페이지로 이동
      if (creationSucceeded && context.mounted) {
        // 페이지 이동 먼저 수행
        _navigateToNoteDetail(context, createdNoteId!, true);
        
        // 페이지 이동 후 로딩 다이얼로그 닫기
        Future.delayed(Duration(milliseconds: 100), () {
          if (context.mounted && isLoadingDialogShowing) {
            isLoadingDialogShowing = false;
            LoadingDialog.hide(context);
          }
        });
        return;
      }
      
      // 실패한 경우 로딩 다이얼로그 닫기
      if (context.mounted && isLoadingDialogShowing) {
        isLoadingDialogShowing = false;
        LoadingDialog.hide(context);
      }
      
      // 오류 메시지 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('노트 생성 중 오류가 발생했습니다'),
            backgroundColor: ColorTokens.error,
            behavior: UITokens.snackBarTheme.behavior,
            shape: UITokens.snackBarTheme.shape,
          ),
        );
      }
    }
  }
  
  // 노트 상세 화면으로 이동하는 메서드
  void _navigateToNoteDetail(BuildContext context, String noteId, bool isProcessingBackground) {
    if (!context.mounted) return;
    
    // Microtask로 이동하여 화면 깜빡임 방지
    Future.microtask(() {
      if (context.mounted) {
        // 화면 전환 (replace 사용하여 현재 화면 대체)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => NoteDetailScreen(
              noteId: noteId,
              isProcessingBackground: isProcessingBackground,
            ),
          ),
        );
      }
    });
  }
} 