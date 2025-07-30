import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

/// 이미지 압축 결과를 나타내는 클래스
/// 
/// [success]: 압축 성공 여부
/// [error]: 실패 시 에러 메시지
/// [targetPath]: 압축된 이미지의 저장 경로
class CompressionResult {
  final bool success;
  final String? error;
  final String? targetPath;
  
  CompressionResult({
    required this.success,
    this.error,
    this.targetPath,
  });
  
  factory CompressionResult.success(String path) => 
    CompressionResult(success: true, targetPath: path);
  
  factory CompressionResult.failure(String error) => 
    CompressionResult(success: false, error: error);
}

/// 이미지 압축 및 최적화를 담당하는 클래스
/// 
/// 싱글톤 패턴으로 구현되어 있으며, 다음과 같은 기능을 제공합니다:
/// 1. FlutterImageCompress를 사용한 기본 압축
/// 2. 기본 압축 실패 시 image 패키지를 사용한 대체 압축
/// 3. 이미지 크기 조정 및 포맷 최적화
class ImageCompression {
  static final ImageCompression _instance = ImageCompression._internal();
  factory ImageCompression() => _instance;

  ImageCompression._internal();

  /// 이미지 압축 및 최적화
  /// 
  /// [imagePath]: 압축할 원본 이미지 경로
  /// [maxDimension]: 이미지의 최대 크기 (너비 또는 높이)
  /// [quality]: 압축 품질 (0-100)
  /// [targetPath]: 압축된 이미지의 저장 경로 (지정하지 않으면 자동 생성)
  /// 
  /// 압축 과정:
  /// 1. FlutterImageCompress로 압축 시도
  /// 2. 실패 시 image 패키지로 대체 압축
  /// 3. 이미지 크기가 maxDimension을 초과하면 리사이징
  /// 4. JPG 압축 시도 후 실패하면 PNG로 저장
  Future<CompressionResult> compressAndOptimizeImage(
    String imagePath, {
    int maxDimension = 1280,
    int quality = 70,
    String? targetPath,
  }) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return CompressionResult.failure('원본 이미지 파일을 찾을 수 없습니다: $imagePath');
      }

      // 타겟 경로가 없으면 자동 생성
      final String finalTargetPath = targetPath ?? 
          '${path.dirname(imagePath)}/compressed_${path.basename(imagePath)}';

      // FlutterImageCompress로 압축 시도 (속도 최적화 설정)
      try {
        final result = await FlutterImageCompress.compressAndGetFile(
          imagePath,
          finalTargetPath,
          minWidth: maxDimension,
          minHeight: maxDimension,
          quality: quality,
          format: CompressFormat.jpeg,
        );

        if (result != null) {
          if (kDebugMode) {
            final originalSize = await getImageSize(imagePath);
            final compressedSize = await getImageSize(result.path);
            debugPrint('🖼️ 이미지 압축 완료: ${formatSize(originalSize)} → ${formatSize(compressedSize)}');
          }
          return CompressionResult.success(result.path);
        }
      } catch (e) {
        debugPrint('FlutterImageCompress 압축 실패: $e');
      }

      // FlutterImageCompress 실패 시 image 패키지로 시도 (간단한 처리)
      try {
        final bytes = await file.readAsBytes();
        var image = img.decodeImage(bytes);
        
        if (image == null) {
          return CompressionResult.failure('이미지 디코딩 실패');
        }

        // 더 적극적인 리사이징 (속도 우선) - NaN 방지
        if (image.width > maxDimension || image.height > maxDimension) {
          // 이미지 크기가 유효한지 확인
          if (image.width <= 0 || image.height <= 0) {
            return CompressionResult.failure('유효하지 않은 이미지 크기: ${image.width}x${image.height}');
          }
          
          double ratio = (image.width > image.height)
              ? maxDimension / image.width
              : maxDimension / image.height;
              
          // ratio가 유효한지 확인 (NaN, Infinity 방지)
          if (!ratio.isFinite || ratio <= 0) {
            return CompressionResult.failure('유효하지 않은 리사이징 비율: $ratio');
          }
          
          final newWidth = (image.width * ratio).round();
          final newHeight = (image.height * ratio).round();
          
          // 최종 크기가 유효한지 확인
          if (newWidth <= 0 || newHeight <= 0) {
            return CompressionResult.failure('유효하지 않은 리사이징 결과: ${newWidth}x${newHeight}');
          }
          
          image = img.copyResize(
            image,
            width: newWidth,
            height: newHeight,
            interpolation: img.Interpolation.linear,
          );
        }

        // JPG만 사용 (PNG 제거로 속도 향상)
        final jpegBytes = img.encodeJpg(image, quality: quality);
        await File(finalTargetPath).writeAsBytes(jpegBytes);
        return CompressionResult.success(finalTargetPath);
      } catch (e) {
        return CompressionResult.failure('이미지 압축 실패: $e');
      }
    } catch (e) {
      return CompressionResult.failure('이미지 처리 중 오류: $e');
    }
  }

  /// 빠른 이미지 압축 (노트 생성용 - 최대 속도 우선)
  Future<CompressionResult> compressForUpload(String imagePath) async {
    return compressAndOptimizeImage(
      imagePath,
      maxDimension: 1024,
      quality: 60,
    );
  }

  /// 이미지 파일의 크기를 바이트 단위로 반환
  /// 
  /// [imagePath]: 크기를 확인할 이미지 파일 경로
  /// 반환값: 이미지 파일의 크기 (바이트)
  Future<int> getImageSize(String imagePath) async {
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      debugPrint('이미지 크기 확인 중 오류: $e');
      return 0;
    }
  }

  /// 바이트 크기를 사람이 읽기 쉬운 형식으로 변환
  /// 
  /// [bytes]: 변환할 바이트 크기
  /// 반환값: "B", "KB", "MB", "GB" 단위로 변환된 문자열
  String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
