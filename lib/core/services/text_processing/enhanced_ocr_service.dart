// 향후 다국어 지원 확대 예정
// 현재는 중국어 텍스트 추출에 초점
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/vision/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import '../storage/unified_cache_service.dart';

/// Enhanced OCR Service: 이미지에서 텍스트를 추출하는 서비스
///
/// Google Cloud Vision API를 사용하여 이미지에서 텍스트를 추출합니다.
/// OCR 기능에만 집중하도록 단순화되었습니다.
/// 텍스트 처리 관련 로직은 TextProcessingWorkflow로 이동했습니다.
class EnhancedOcrService {
  // 싱글톤 패턴
  static final EnhancedOcrService _instance = EnhancedOcrService._internal();
  factory EnhancedOcrService() => _instance;
  EnhancedOcrService._internal() {
    debugPrint('✨ EnhancedOcrService: 생성자 호출됨');
    _initializeApi();
  }

  // API 클라이언트
  AutoRefreshingAuthClient? _client;
  VisionApi? _visionApi;
  
  // 캐시 서비스
  final UnifiedCacheService _cacheService = UnifiedCacheService();

  /// API 클라이언트 초기화
  Future<void> _initializeApi() async {
    try {
      final serviceAccountCredentials = await _loadServiceAccountCredentials();
      if (serviceAccountCredentials != null) {
        final scopes = [VisionApi.cloudPlatformScope];
        _client = await clientViaServiceAccount(serviceAccountCredentials, scopes);
        _visionApi = VisionApi(_client!);
        debugPrint('Google Cloud Vision API 초기화 완료');
      } else {
        debugPrint('서비스 계정 자격 증명을 로드할 수 없습니다.');
      }
    } catch (e) {
      debugPrint('Vision API 초기화 중 오류 발생: $e');
    }
  }

  /// 서비스 계정 자격 증명 로드
  Future<ServiceAccountCredentials?> _loadServiceAccountCredentials() async {
    try {
      // 자격 증명 파일 경로 (앱 내부 디렉토리에 저장된 경우)
      final appDir = await getApplicationDocumentsDirectory();
      final credentialFilePath = '${appDir.path}/service-account.json';
      final credentialFile = File(credentialFilePath);
      
      if (await credentialFile.exists()) {
        final credentialJson = await credentialFile.readAsString();
        return ServiceAccountCredentials.fromJson(jsonDecode(credentialJson));
      } else {
        debugPrint('자격 증명 파일을 찾을 수 없습니다: $credentialFilePath');
        return null;
      }
    } catch (e) {
      debugPrint('자격 증명 로드 중 오류 발생: $e');
      return null;
    }
  }

  /// 이미지에서 텍스트 추출
  /// 
  /// [imageFile]: 텍스트를 추출할 이미지 파일
  /// [skipUsageCount]: 사용량 카운트 스킵 여부 (테스트용)
  Future<String> extractText(File imageFile, {bool skipUsageCount = false}) async {
    try {
      // 이미지 파일 해시 생성 (캐싱 키로 사용)
      final imageHash = await _generateImageHash(imageFile);
      
      // 캐시에서 OCR 결과 확인
      final cachedOcrResult = await _cacheService.getImageOcrResult(imageHash);
      if (cachedOcrResult != null && cachedOcrResult.isNotEmpty) {
        debugPrint('캐시에서 OCR 결과 반환: ${cachedOcrResult.length} 자');
        return cachedOcrResult;
      }
      
      // API가 초기화되지 않은 경우 초기화
      if (_visionApi == null || _client == null) {
        await _initializeApi();
        
        // 여전히 초기화되지 않은 경우 에러
        if (_visionApi == null || _client == null) {
          throw Exception('Vision API가 초기화되지 않았습니다.');
        }
      }
      
      // 이미지 파일을 바이트로 읽기
      final imageBytes = await imageFile.readAsBytes();
      
      // Vision API 요청 생성
      final request = AnnotateImageRequest()
        ..features = [Feature()..type = 'TEXT_DETECTION']
        ..image = (Image()..content = base64Encode(imageBytes));
      
      final batchRequest = BatchAnnotateImagesRequest()
        ..requests = [request];
      
      // OCR 요청 실행
      final response = await _visionApi!.images.annotate(batchRequest);
      
      // 응답 처리
      if (response.responses != null && response.responses!.isNotEmpty) {
        final firstResponse = response.responses!.first;
        final extractedText = firstResponse.fullTextAnnotation?.text ?? '';
        
        // OCR 결과 캐싱
        if (extractedText.isNotEmpty) {
          await _cacheService.setImageOcrResult(imageHash, extractedText);
        }
        
        debugPrint('이미지에서 텍스트 추출 완료: ${extractedText.length} 자');
        return extractedText;
      }
      
      return '';
    } catch (e) {
      debugPrint('텍스트 추출 중 오류 발생: $e');
      return '';
    }
  }

  /// 이미지 파일의 해시 생성 (캐싱 키로 사용)
  Future<String> _generateImageHash(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      
      // 대용량 이미지의 경우 첫 10KB만 사용 (성능 최적화)
      final sampleSize = min(10 * 1024, bytes.length);
      final sample = bytes.sublist(0, sampleSize);
      
      // SHA-256 해시 생성
      final digest = sha256.convert(sample);
      return digest.toString();
    } catch (e) {
      debugPrint('이미지 해시 생성 중 오류 발생: $e');
      
      // 오류 시 파일 경로와 타임스탬프로 대체
      final fallbackKey = '${imageFile.path}_${DateTime.now().millisecondsSinceEpoch}';
      return sha256.convert(utf8.encode(fallbackKey)).toString();
    }
  }
}
