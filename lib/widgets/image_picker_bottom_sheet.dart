import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';  // min 함수를 위한 import 추가
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
  
  @override
  void dispose() {
    // dispose 될 때 처리 상태 초기화
    _isProcessing = false;
    super.dispose();
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
    return WillPopScope(
      onWillPop: () {
        // 뒤로가기 시 처리 상태 초기화
        setState(() {
          _isProcessing = false;
        });
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
                      // X 버튼 클릭시 처리 상태 초기화 후 닫기
                      setState(() {
                        _isProcessing = false;
                      });
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
          print('이미지 선택이 취소되었습니다.');
        }
        // 처리 중 상태 초기화
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
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
          SnackBar(content: Text('이미지 선택 중 오류: ${kDebugMode ? e.toString() : "이미지를 선택할 수 없습니다. 다시 시도해주세요."}')),
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
              SnackBar(content: Text(kDebugMode ? '노트 생성 중 오류가 발생했습니다: $e' : '노트 생성 중 오류가 발생했습니다. 다시 시도해주세요.')),
            );
          }
        } finally {
          // 처리 완료 후 상태 초기화 (추가)
          _isProcessing = false;
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
    
    // 시뮬레이터에서 실행 중인지 확인 (iOS 시뮬레이터에서는 카메라가 작동하지 않음)
    bool isSimulator = false;
    if (Platform.isIOS) {
      try {
        // 간단한 시뮬레이터 확인 방법 - 실제 디바이스에는 '/Applications' 경로가 없음
        isSimulator = await File('/Applications').exists();
      } catch (e) {
        // 확인 실패 시 기본적으로 시뮬레이터가 아니라고 가정
        isSimulator = false;
      }
    }
    
    if (isSimulator) {
      if (kDebugMode) {
        print('iOS 시뮬레이터에서는 카메라를 사용할 수 없습니다.');
      }
      
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        
        // 시뮬레이터용 얼럿 표시 (스낵바 대신 얼럿 사용)
        _showSingleAlert(
          '카메라 사용 불가',
          'iOS 시뮬레이터에서는 카메라 기능을 사용할 수 없습니다. 실제 기기에서 테스트해주세요.'
        );
      }
      return;
    }
    
    // iOS 18.4 버전 확인 (카메라 문제가 있는 버전)
    bool isIOS184OrLater = false;
    if (Platform.isIOS) {
      try {
        final String platformVersion = Platform.operatingSystemVersion;
        if (kDebugMode) {
          print('iOS 버전: $platformVersion');
        }
        
        // 버전 체크 (18.4 이상 확인)
        if (platformVersion.contains('18.4') || 
            platformVersion.contains('18.5') || 
            platformVersion.contains('18.6') || 
            platformVersion.contains('19.')) {
          isIOS184OrLater = true;
          if (kDebugMode) {
            print('iOS 18.4 이상 버전 감지됨: $platformVersion');
          }
        }
      } catch (e) {
        // 버전 확인 실패 시 기본값
        isIOS184OrLater = false;
      }
    }
    
    // iOS 18.4 이상에서 카메라 사용 시 사전 경고
    if (isIOS184OrLater && mounted) {
      // 카메라 시도 전에 상태 초기화
      setState(() {
        _isProcessing = false;
      });
      
      // 경고 대화상자 표시
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('안내'),
            content: const Text(
              'iOS 18.4 버전에서는 카메라 접근에 문제가 있을 수 있습니다. '
              '오류가 발생할 경우, 갤러리에서 이미지를 선택하는 방법을 이용해주세요.'
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true); // 계속 진행
                },
                child: const Text('계속 진행'),
              ),
            ],
          );
        },
      ).then((continueCamera) {
        if (continueCamera == true) {
          // 계속 진행 선택 시 다시 처리 상태 활성화하고 실제 카메라 실행
          if (mounted) {
            setState(() {
              _isProcessing = true;
            });
            _executeCameraPickerWithErrorHandling();
          }
        }
      });
      
      return; // 대화상자에서 처리되므로 여기서 종료
    } else {
      // iOS 18.4가 아니거나 다른 플랫폼인 경우 바로 실행
      await _executeCameraPickerWithErrorHandling();
    }
  }
  
  // 카메라 실행 및 오류 처리를 담당하는 별도 메서드 (중복 코드 방지)
  Future<void> _executeCameraPickerWithErrorHandling() async {
    if (!mounted) {
      _isProcessing = false;
      return;
    }
    
    // 작업 시작 - 카메라 준비 중임을 사용자에게 알립니다
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('카메라를 준비하는 중...'),
        duration: Duration(seconds: 1),
      ),
    );
    
    File? imageFile;
    String? errorMessage;
    
    try {
      if (kDebugMode) {
        print('이미지 선택 시작: ImageSource.camera');
      }
      
      // iOS에서 권장되는 최신 방식으로 먼저 시도
      if (Platform.isIOS) {
        try {
          final XFile? photo = await _picker.pickImage(
            source: ImageSource.camera,
            requestFullMetadata: false,
            maxWidth: 1920,
            maxHeight: 1080,
            imageQuality: 80,
          );
          
          if (photo != null) {
            imageFile = File(photo.path);
          } else {
            if (kDebugMode) {
              print('iOS 카메라 선택이 취소되었거나 실패했습니다.');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('iOS 카메라 접근 중 오류 발생: $e');
          }
          errorMessage = '카메라 접근 중 오류가 발생했습니다.';
        }
      } else {
        // 안드로이드나 다른 플랫폼용 기본 방식
        imageFile = await _imageService.pickImage(source: ImageSource.camera);
      }
      
      // 이전 방법이 실패했고 아직 오류 메시지가 없는 경우 다른 방법 시도
      if (imageFile == null && errorMessage == null) {
        if (kDebugMode) {
          print('첫 번째 방법 실패, 대체 방법 시도');
        }
        
        try {
          // 다른 설정으로 시도
          final XFile? photo = await _picker.pickImage(
            source: ImageSource.camera,
            requestFullMetadata: false,
            maxWidth: 1280,  // 해상도 낮춤
            maxHeight: 720,
          );
          
          if (photo != null) {
            imageFile = File(photo.path);
          } else {
            if (kDebugMode) {
              print('카메라 선택이 취소되었습니다.');
            }
            // 명시적인 취소는 오류가 아님
            if (mounted) {
              setState(() {
                _isProcessing = false;
              });
              return;
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('두 번째 시도 중 오류: $e');
          }
          errorMessage = '카메라를 열 수 없습니다.';
        }
      }
      
      // 이미지 파일을 얻었으면 성공
      if (imageFile != null) {
        // 이미지를 선택한 후에 바텀시트를 닫습니다
        if (mounted) {
          // 루트 컨텍스트 가져오기
          final BuildContext rootContext = Navigator.of(context, rootNavigator: true).context;
          
          // 바텀 시트 닫기
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
              await _noteCreationWorkflow.createNoteWithImages(
                rootContext, 
                [imageFile!], // null이 아님을 확신하므로 !로 강제 변환
                closeBottomSheet: false,
                showLoadingDialog: false
              );
            } catch (e) {
              if (kDebugMode) {
                print('이미지 처리 중 오류: $e');
              }
              
              // 오류 발생 시 로딩 화면 닫기
              if (rootContext.mounted) {
                NoteCreationLoader.hide(rootContext);
                
                // 사용자에게 오류 알림
                _showSingleAlert(
                  '처리 오류',
                  kDebugMode 
                    ? '노트 생성 중 오류가 발생했습니다: $e' 
                    : '노트 생성 중 오류가 발생했습니다. 다시 시도해주세요.',
                  context: rootContext
                );
              }
            } finally {
              // 처리 완료 후 상태 초기화
              _isProcessing = false;
            }
          });
        } else {
          _isProcessing = false;
        }
      } 
      // 이미지 파일을 얻지 못했고 오류 메시지가 있는 경우
      else if (errorMessage != null) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
          
          // iOS 18.4 버전에 맞는 메시지
          final String message = Platform.isIOS 
            ? 'iOS 18.4 버전에서는 카메라 접근에 제한이 있을 수 있습니다. 갤러리에서 이미지를 선택해주세요.'
            : '카메라를 열 수 없습니다. 갤러리에서 이미지를 선택해주세요.';
          
          _showSingleAlert('카메라 사용 불가', message);
        } else {
          _isProcessing = false;
        }
      } 
      // 이미지 파일도 없고 오류 메시지도 없는 경우 (사용자가 취소한 경우)
      else {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        } else {
          _isProcessing = false;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('카메라 처리 중 예상치 못한 오류: $e');
      }
      
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        
        _showSingleAlert(
          '카메라 오류',
          kDebugMode 
            ? '카메라 사용 중 오류가 발생했습니다: ${e.toString().substring(0, min(e.toString().length, 100))}' 
            : '카메라를 사용할 수 없습니다. 갤러리에서 이미지를 선택해주세요.'
        );
      } else {
        _isProcessing = false;
      }
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