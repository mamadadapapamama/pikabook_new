import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import 'package:path_provider/path_provider.dart';

/// 이미지를 전체 화면으로 표시하는 화면
class FullImageScreen extends StatefulWidget {
  final File? imageFile;
  final String? imageUrl;
  final String title;

  const FullImageScreen({
    Key? key,
    this.imageFile,
    this.imageUrl,
    this.title = '이미지 보기',
  }) : super(key: key);

  @override
  State<FullImageScreen> createState() => _FullImageScreenState();
}

class _FullImageScreenState extends State<FullImageScreen> {
  final TransformationController _transformationController =
      TransformationController();
  late TapDownDetails _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    // 디버그 타이머 방지 (디버그 모드에서만)
    if (kDebugMode) {
      timeDilation = 1.0;
    }
    // 화면 진입 시 상태표시줄을 흰색으로 설정 (강제 적용)
    _setLightStatusBar();
  }

  // 상태표시줄을 밝은색(흰색)으로 설정
  void _setLightStatusBar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 상태표시줄 설정을 강제로 적용
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // 안드로이드용 (흰색 아이콘)
        statusBarBrightness: Brightness.dark, // iOS용 (어두운 배경 = 흰색 아이콘)
      ));
    });
  }



  @override
  void dispose() {
    // 디버그 타이머 방지 (디버그 모드에서만)
    if (kDebugMode) {
      timeDilation = 1.0;
    }
    
    _transformationController.dispose();
    // 화면을 떠날 때 상태표시줄을 다시 검은색으로 복원
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark, // 안드로이드용 (검정 아이콘)
      statusBarBrightness: Brightness.light, // iOS용 (밝은 배경 = 검정 아이콘)
    ));
    super.dispose();
  }
  
  // 뒤로가기 버튼 처리
  Future<bool> _onWillPop() async {
    // 디버그 타이머 방지 (디버그 모드에서만)
    if (kDebugMode) {
      timeDilation = 1.0;
    }
    
    // 화면을 떠날 때 상태표시줄을 다시 검은색으로 복원
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark, // 안드로이드용 (검정 아이콘)
      statusBarBrightness: Brightness.light, // iOS용 (밝은 배경 = 검정 아이콘)
    ));
    
    // 리소스 정리 후 화면 종료
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    
    return false; // 뒤로가기 이벤트 소비
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      // 현재 확대된 상태면 원래 크기로 복원
      _transformationController.value = Matrix4.identity();
    } else {
      // 원래 크기면 두 배로 확대하고 탭한 위치를 중심으로 설정
      final position = _doubleTapDetails.localPosition;
      final double scale = 2.5;

      final x = -position.dx * (scale - 1);
      final y = -position.dy * (scale - 1);

      final zoomed = Matrix4.identity()
        ..translate(x, y)
        ..scale(scale);

      _transformationController.value = zoomed;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 디버그 타이머 방지 (디버그 모드에서만)
    if (kDebugMode) {
      timeDilation = 1.0;
    }
    
    // 검은 배경에 흰색 상태표시줄을 설정
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(
            widget.title,
            style: TypographyTokens.subtitle2.copyWith(color: ColorTokens.textLight),
          ),
          backgroundColor: Colors.black.withOpacity(0.5),
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white), // 뒤로 가기 버튼 색상을 흰색으로 설정
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: () => _onWillPop(),
          ),
          systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light, // Android (흰색 아이콘)
            statusBarBrightness: Brightness.dark, // iOS (어두운 배경 = 흰색 아이콘)
          ),
        ),
        body: SafeArea(
          child: Center(
            child: GestureDetector(
              onDoubleTapDown: _handleDoubleTapDown,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.5,
                maxScale: 4.0,
                child: _buildImage(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    // 파일 이미지 처리
    if (widget.imageFile != null) {
      final bool fileExists = widget.imageFile!.existsSync();
      final int fileSize = fileExists ? widget.imageFile!.lengthSync() : 0;
      
      if (kDebugMode) {
        debugPrint('🖼️ 📁 파일에서 직접 로드: 존재=$fileExists, 크기=${fileSize}bytes');
      }
      
      if (fileExists && fileSize > 0) {
        return Image.file(
          widget.imageFile!,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            if (kDebugMode) {
              debugPrint('🖼️ ❌ 파일 로드 에러: $error');
            }
            return _buildPlaceholderImage();
          },
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            // 첫 프레임이 로드되면 바로 표시 (깜빡임 방지)
            if (wasSynchronouslyLoaded) return child;
            return frame != null ? child : _buildPlaceholderImage();
          },
        );
      } else {
        return _buildPlaceholderImage();
      }
    } 
    else if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      final imageUrl = widget.imageUrl!;
      
      // assets 이미지 경로 처리
      if (imageUrl.startsWith('assets/')) {
        return Image.asset(
          imageUrl,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            if (kDebugMode) {
              debugPrint('🖼️ ❌ Asset 로드 에러: $error');
            }
            return _buildPlaceholderImage();
          },
        );
      }
      
      // 상대 경로인 경우
      if (imageUrl.startsWith('images/')) {
        return FutureBuilder<String>(
          future: _getFullImagePath(imageUrl),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildPlaceholderImage();
            } else if (snapshot.hasData && snapshot.data != null) {
              final imagePath = snapshot.data!;
              final imageFile = File(imagePath);
              
              if (imageFile.existsSync()) {
                return Image.file(
                  imageFile,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (context, error, stackTrace) {
                    if (kDebugMode) {
                      debugPrint('🖼️ ❌ 상대 경로 파일 로드 에러: $error');
                    }
                    return _buildPlaceholderImage();
                  },
                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                    // 첫 프레임이 로드되면 바로 표시 (깜빡임 방지)
                    if (wasSynchronouslyLoaded) return child;
                    return frame != null ? child : _buildPlaceholderImage();
                  },
                );
              } else {
                return _buildPlaceholderImage();
              }
            } else {
              return _buildPlaceholderImage();
            }
          },
        );
      } else {
        // 일반 URL인 경우
        return Image.network(
          imageUrl,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                color: ColorTokens.textLight,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            if (kDebugMode) {
              debugPrint('🖼️ ❌ 네트워크 이미지 로드 에러: $error');
            }
            return _buildPlaceholderImage();
          },
        );
      }
    } 
    else {
      if (kDebugMode) {
        debugPrint('🖼️ ⚠️ 이미지 정보 없음');
      }
      return _buildPlaceholderImage();
    }
  }

  // 기본 이미지 위젯 (placeholder)
  Widget _buildPlaceholderImage() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey[100],
      child: Image.asset(
        'assets/images/image_empty.png',
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildLoadingWidget(ImageChunkEvent? loadingProgress) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            value: loadingProgress == null
                ? null
                : loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!,
            color: ColorTokens.textLight,
          ),
          SizedBox(height: SpacingTokens.md),
          Text(
            '이미지 로딩 중...',
            style: TypographyTokens.body2.copyWith(color: ColorTokens.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image,
          size: SpacingTokens.iconSizeXLarge + SpacingTokens.iconSizeMedium,
          color: ColorTokens.textLight.withOpacity(0.54),
        ),
        SizedBox(height: SpacingTokens.md),
        Text(
          '이미지를 불러올 수 없습니다',
          style: TypographyTokens.body2.copyWith(color: ColorTokens.textLight),
        ),
      ],
    );
  }

  // 상대 경로를 절대 경로로 변환
  Future<String> _getFullImagePath(String relativePath) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$relativePath';
  }
}
