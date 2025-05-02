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
import '../core/services/media/image_service.dart';
import '../core/widgets/loading_dialog_experience.dart';

class ImagePickerBottomSheet extends StatefulWidget {
  const ImagePickerBottomSheet({Key? key}) : super(key: key);

  @override
  State<ImagePickerBottomSheet> createState() => _ImagePickerBottomSheetState();
}

class _ImagePickerBottomSheetState extends State<ImagePickerBottomSheet> {
  final UsageLimitService _usageLimitService = UsageLimitService();
  final NoteCreationWorkflow _noteCreationWorkflow = NoteCreationWorkflow();
  final ImagePicker _picker = ImagePicker();
  final ImageService _imageService = ImageService();
  bool _isButtonDisabled = false;
  String _limitTooltip = '';
  
  // 이미지 처리 중인지 추적하는 변수 추가
  bool _isProcessing = false;
  
  // 사용량 확인 관련 변수 추가
  bool _isCheckingLimits = false;
  DateTime? _lastCheckTime;
  
  @override
  void initState() {
    super.initState();
    // UI를 먼저 표시하고 사용량은 백그라운드에서 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUsageLimits();
    });
  }
  
  // 사용량 한도 확인
  Future<void> _checkUsageLimits() async {
    // 이미 확인 중이면 중복 호출 방지
    if (_isCheckingLimits) {
      if (kDebugMode) {
        debugPrint('사용량 확인이 이미 진행 중입니다. 중복 호출 방지');
      }
      return;
    }
    
    // 최근 10초 이내에 확인했으면 재확인 건너뜀
    final now = DateTime.now();
    if (_lastCheckTime != null && now.difference(_lastCheckTime!).inSeconds < 10) {
      if (kDebugMode) {
        debugPrint('사용량 최근에 확인함 (${now.difference(_lastCheckTime!).inSeconds}초 전)');
      }
      return;
    }
    
    _isCheckingLimits = true;
    
    try {
      final limitStatus = await _usageLimitService.checkFreeLimits(withBuffer: true);
      _lastCheckTime = DateTime.now();
      
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
    } finally {
      // 확인 중 상태 해제
      _isCheckingLimits = false;
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
    // 이미 처리 중이면 중복 호출 방지
    if (_isProcessing) {
      if (kDebugMode) {
        print('이미지 선택 처리가 이미 진행 중입니다. 중복 호출 방지.');
      }
      return;
    }
    
    // 처리 중 상태로 설정
    setState(() {
      _isProcessing = true;
    });
    
    // 작업 시작 - 이미지 선택 중임을 사용자에게 알립니다
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이미지를 선택하는 중...'),
        duration: Duration(seconds: 1),
      ),
    );
    
    List<XFile>? selectedImages;
    
    try {
      // 압축 문제를 피하기 위해 imageQuality 파라미터를 제거하고 원본 품질 사용
      selectedImages = await _picker.pickMultiImage(
        requestFullMetadata: false, // 불필요한 메타데이터 요청 안함
      );
        
      // 이미지 선택이 취소되었거나 이미지가 없는 경우
      if (selectedImages == null || selectedImages.isEmpty) {
        if (kDebugMode) {
          print('이미지 선택이 취소되었거나 이미지가 없습니다.');
        }
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error picking images: $e');
      }
      if (mounted) {
        // 처리 중 상태 초기화
        setState(() {
          _isProcessing = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 선택 중 오류: $e')),
        );
      }
      return;
    }
    
    // 이미지를 선택한 후에 바텀시트를 닫습니다 (강력한 방식 적용)
    if (mounted) {
      // 루트 컨텍스트 가져오기
      final BuildContext rootContext = Navigator.of(context, rootNavigator: true).context;
      
      // 바텀 시트 닫기 (물리적 뒤로가기 제스처 동작과 동일하게)
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
        
        // 안정성을 위해 약간의 딜레이 추가
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      // 로딩 화면 표시
      if (rootContext.mounted) {
        await NoteCreationLoader.show(
          rootContext, 
          message: '스마트 노트를 만들고 있어요.\n잠시만 기다려 주세요!'
        );
      }
      
      // 메인 UI 스레드에서 작업을 분리하기 위해 마이크로태스크 큐에 작업 예약
      Future.microtask(() async {
        try {
          // XFile에서 File로 변환
          final List<File> imageFiles = selectedImages!
              .map((xFile) => File(xFile.path))
              .toList();
          
          // 이미지가 유효한 경우 노트 생성 시작
          // 이미 로딩 화면이 표시되었으므로 showLoadingDialog=false
          await _noteCreationWorkflow.createNoteWithImages(
            rootContext, 
            imageFiles,
            closeBottomSheet: false, // 이미 바텀시트를 닫았으므로 false로 설정
            showLoadingDialog: false  // 이미 로딩 화면이 표시되었으므로 false로 설정
          );
        } catch (e) {
          if (kDebugMode) {
            print('이미지 처리 중 오류: $e');
          }
          
          // 오류 발생 시 로딩 화면 닫기
          if (rootContext.mounted) {
            NoteCreationLoader.hide(rootContext);
            
            // 사용자에게 오류 알림
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(content: Text('노트 생성 중 오류가 발생했습니다: $e')),
            );
          }
        }
      });
    }
  }
  
  /// 카메라로 사진 촬영
  Future<void> _takeCameraPhoto() async {
    // 이미 처리 중이면 중복 호출 방지
    if (_isProcessing) {
      if (kDebugMode) {
        print('카메라 촬영 처리가 이미 진행 중입니다. 중복 호출 방지.');
      }
      return;
    }
    
    // 처리 중 상태로 설정
    setState(() {
      _isProcessing = true;
    });
    
    // 작업 시작 - 카메라 준비 중임을 사용자에게 알립니다
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('카메라를 준비하는 중...'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    
    File? imageFile;
    
    try {
      // 먼저 ImageService의 pickImage 메서드를 사용 (가장 최적화된 방법)
      imageFile = await _imageService.pickImage(source: ImageSource.camera);
      
      // 실패한 경우 직접 ImagePicker 사용
      if (imageFile == null) {
        if (kDebugMode) {
          print('ImageService.pickImage 실패, 직접 ImagePicker 시도');
        }
        
        // iOS 18에 최적화된 설정으로 시도
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          requestFullMetadata: false,
          // 추가 옵션
          maxWidth: 1920,  // 적절한 해상도 제한
          maxHeight: 1080,
        );
        
        // 사진 촬영이 취소되었거나 이미지가 없는 경우
        if (photo == null) {
          if (kDebugMode) {
            print('사진 촬영이 취소되었습니다.');
          }
          // 처리 중 상태 초기화
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
          }
          return;
        }
        
        imageFile = File(photo.path);
      }
      
      // 마지막 대안으로 대체 메서드 시도
      if (imageFile == null) {
        if (kDebugMode) {
          print('표준 방법 실패, 대체 메서드 시도');
        }
        imageFile = await _imageService.pickImageAlternative(source: ImageSource.camera);
      }
      
      // 여전히 실패한 경우 종료
      if (imageFile == null) {
        if (kDebugMode) {
          print('모든 카메라 시도 실패');
        }
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('카메라를 열 수 없습니다. 기기 설정에서 카메라 접근 권한을 확인해주세요.')),
          );
        }
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error taking photo: $e');
      }
      if (mounted) {
        // 처리 중 상태 초기화
        setState(() {
          _isProcessing = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('카메라 촬영 중 오류: $e')),
        );
      }
      return;
    }
    
    // 이미지를 선택한 후에 바텀시트를 닫습니다 (강력한 방식 적용)
    if (mounted) {
      // 루트 컨텍스트 가져오기
      final BuildContext rootContext = Navigator.of(context, rootNavigator: true).context;
      
      // 바텀 시트 닫기 (물리적 뒤로가기 제스처 동작과 동일하게)
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
        
        // 안정성을 위해 약간의 딜레이 추가 
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      // 로딩 화면 표시
      if (rootContext.mounted) {
        await NoteCreationLoader.show(
          rootContext, 
          message: '스마트 노트를 만들고 있어요.\n잠시만 기다려 주세요!'
        );
      }
      
      // 메인 UI 스레드에서 작업을 분리하기 위해 마이크로태스크 큐에 작업 예약
      Future.microtask(() async {
        try {
          // 이미지가 유효한 경우 노트 생성 시작
          // 이미 로딩 화면이 표시되었으므로 showLoadingDialog=false
          await _noteCreationWorkflow.createNoteWithImages(
            rootContext, 
            [imageFile!],
            closeBottomSheet: false, // 이미 바텀시트를 닫았으므로 false로 설정
            showLoadingDialog: false  // 이미 로딩 화면이 표시되었으므로 false로 설정
          );
        } catch (e) {
          if (kDebugMode) {
            print('이미지 처리 중 오류: $e');
          }
          
          // 오류 발생 시 로딩 화면 닫기
          if (rootContext.mounted) {
            NoteCreationLoader.hide(rootContext);
            
            // 사용자에게 오류 알림
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(content: Text('노트 생성 중 오류가 발생했습니다: $e')),
            );
          }
        }
      });
    }
  }
} 