import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';

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
  void dispose() {
    _transformationController.dispose();
    super.dispose();
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
    // 검은색 배경에서는 흰색 아이콘으로 설정
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: TypographyTokens.subtitle2.copyWith(color: ColorTokens.textLight),
        ),
        backgroundColor: ColorTokens.black,
        foregroundColor: ColorTokens.textLight,
        elevation: 0,
      ),
      backgroundColor: ColorTokens.black,
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
    );
  }

  Widget _buildImage() {
    if (widget.imageFile != null) {
      return Image.file(
        widget.imageFile!,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          return _buildErrorWidget();
        },
      );
    } else if (widget.imageUrl != null) {
      return Image.network(
        widget.imageUrl!,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildLoadingWidget(loadingProgress);
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildErrorWidget();
        },
      );
    } else {
      return _buildErrorWidget();
    }
  }

  Widget _buildLoadingWidget(ImageChunkEvent loadingProgress) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                : null,
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
}
