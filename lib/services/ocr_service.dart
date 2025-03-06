import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/vision/v1.dart' as vision;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class OcrService {
  // 싱글톤 패턴 구현
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal();

  // Google Cloud Vision API 클라이언트
  vision.VisionApi? _visionApi;

  // 감지할 언어 설정 (MVP에서는 중국어만 지원)
  final String _targetLanguage = 'zh-CN'; // 중국어

  // API 초기화
  Future<void> initialize() async {
    if (_visionApi != null) return;

    try {
      // 서비스 계정 키 파일 로드
      final credentialsFile = await _loadCredentialsFile();

      // 인증 클라이언트 생성
      final client = await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(credentialsFile),
        [vision.VisionApi.cloudVisionScope],
      );

      // Vision API 클라이언트 생성
      _visionApi = vision.VisionApi(client);

      debugPrint('Google Cloud Vision API 초기화 완료');
    } catch (e) {
      debugPrint('Google Cloud Vision API 초기화 중 오류 발생: $e');
      throw Exception('OCR 서비스를 초기화할 수 없습니다: $e');
    }
  }

  // 서비스 계정 키 파일 로드
  Future<Map<String, dynamic>> _loadCredentialsFile() async {
    try {
      // 먼저 앱 문서 디렉토리에서 키 파일 확인
      final directory = await getApplicationDocumentsDirectory();
      final credentialsPath = '${directory.path}/google_cloud_credentials.json';
      final file = File(credentialsPath);

      if (await file.exists()) {
        final contents = await file.readAsString();
        return json.decode(contents) as Map<String, dynamic>;
      } else {
        // 앱 문서 디렉토리에 파일이 없으면 assets에서 로드하여 복사
        try {
          // assets에서 키 파일 로드 (service-account.json으로 변경)
          final String jsonString = await rootBundle
              .loadString('assets/credentials/service-account.json');

          // 앱 문서 디렉토리에 파일 저장
          await file.create(recursive: true);
          await file.writeAsString(jsonString);

          return json.decode(jsonString) as Map<String, dynamic>;
        } catch (assetError) {
          debugPrint('assets에서 서비스 계정 키 파일 로드 중 오류 발생: $assetError');
          throw Exception('서비스 계정 키 파일을 찾을 수 없습니다.');
        }
      }
    } catch (e) {
      debugPrint('서비스 계정 키 파일 로드 중 오류 발생: $e');
      throw Exception('서비스 계정 키 파일을 로드할 수 없습니다: $e');
    }
  }

  // 이미지에서 텍스트 추출
  Future<String> extractText(File imageFile) async {
    try {
      await initialize();

      if (_visionApi == null) {
        throw Exception('Vision API가 초기화되지 않았습니다.');
      }

      // 이미지 파일을 base64로 인코딩
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // API 요청 생성
      final request = vision.AnnotateImageRequest()
        ..image = (vision.Image()..content = base64Image)
        ..features = [
          vision.Feature()
            ..type = 'TEXT_DETECTION'
            ..maxResults = 50 // 더 많은 텍스트 블록을 감지하도록 증가
        ]
        ..imageContext = (vision.ImageContext()
          ..languageHints = [_targetLanguage, 'en']); // 중국어와 영어 힌트 추가

      // API 호출
      final response = await _visionApi!.images.annotate(
        vision.BatchAnnotateImagesRequest()..requests = [request],
      );

      // 결과 처리
      final annotations = response.responses?[0];
      if (annotations?.textAnnotations != null &&
          annotations!.textAnnotations!.isNotEmpty) {
        // 첫 번째 항목은 전체 텍스트이므로 건너뛰고, 개별 텍스트 블록을 처리
        final textBlocks = annotations.textAnnotations!.skip(1).toList();

        // 필터링된 텍스트 블록을 저장할 리스트
        final filteredBlocks = <vision.EntityAnnotation>[];

        for (final block in textBlocks) {
          final text = block.description ?? '';

          // 텍스트가 비어있으면 건너뜀
          if (text.isEmpty) continue;

          // 필터링 조건 적용
          if (_shouldKeepTextBlock(text)) {
            filteredBlocks.add(block);
          }
        }

        // 필터링된 텍스트 블록이 없으면 빈 문자열 반환
        if (filteredBlocks.isEmpty) {
          debugPrint('필터링 후 감지된 텍스트 블록이 없습니다.');
          return '';
        }

        // 필터링된 텍스트 블록을 원본 위치에 따라 정렬하고 결합
        final combinedText = _combineTextBlocks(filteredBlocks);
        debugPrint('필터링 후 감지된 텍스트: $combinedText');
        return combinedText;
      }

      return '';
    } catch (e) {
      debugPrint('OCR 텍스트 추출 중 오류 발생: $e');

      // 백업 방법: HTTP 직접 호출
      try {
        return await _extractTextWithHttpRequest(imageFile);
      } catch (httpError) {
        debugPrint('HTTP 요청으로 OCR 시도 중 오류 발생: $httpError');
        throw Exception('이미지에서 텍스트를 추출할 수 없습니다: $e');
      }
    }
  }

  // 텍스트 블록을 필터링하는 메서드
  bool _shouldKeepTextBlock(String text) {
    // 1. 숫자만 있는 경우 제외
    if (RegExp(r'^\d+$').hasMatch(text)) {
      debugPrint('숫자만 있는 텍스트 제외: $text');
      return false;
    }

    // 2. 중국어 문자가 포함되어 있는지 확인
    final hasChineseChars = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);

    // 3. 영어 문자가 포함되어 있는지 확인
    final hasEnglishChars = RegExp(r'[a-zA-Z]').hasMatch(text);

    // 4. 숫자가 포함되어 있는지 확인
    final hasDigits = RegExp(r'\d').hasMatch(text);

    // 중국어가 포함된 경우 유지
    if (hasChineseChars) {
      return true;
    }

    // 영어+숫자 조합인 경우 유지 (예: "Chapter 1")
    if (hasEnglishChars && hasDigits) {
      return true;
    }

    // 그 외의 경우 (한국어, 일본어 등) 제외
    if (!hasChineseChars && !hasEnglishChars) {
      debugPrint('지원되지 않는 언어 텍스트 제외: $text');
      return false;
    }

    // 기본적으로 영어만 있는 경우도 유지 (영어+중국어 조합을 위해)
    return true;
  }

  // 텍스트 블록을 위치에 따라 정렬하고 결합하는 메서드
  String _combineTextBlocks(List<vision.EntityAnnotation> blocks) {
    // 텍스트 블록을 위치(세로 방향)에 따라 정렬
    blocks.sort((a, b) {
      final aY = a.boundingPoly?.vertices?[0].y ?? 0;
      final bY = b.boundingPoly?.vertices?[0].y ?? 0;

      // Y 좌표가 같으면 X 좌표로 정렬 (왼쪽에서 오른쪽으로)
      if ((aY - bY).abs() < 10) {
        final aX = a.boundingPoly?.vertices?[0].x ?? 0;
        final bX = b.boundingPoly?.vertices?[0].x ?? 0;
        return aX.compareTo(bX);
      }

      return aY.compareTo(bY);
    });

    // 정렬된 블록을 결합
    final buffer = StringBuffer();
    int? lastY;

    for (final block in blocks) {
      final text = block.description ?? '';
      final y = block.boundingPoly?.vertices?[0].y ?? 0;

      // 새로운 줄인지 확인 (Y 좌표가 이전 블록과 충분히 다른 경우)
      if (lastY != null && (y - lastY).abs() > 10) {
        buffer.write('\n');
      } else if (lastY != null) {
        // 같은 줄의 다른 블록이면 공백 추가
        buffer.write(' ');
      }

      buffer.write(text);
      lastY = y;
    }

    return buffer.toString();
  }

  // HTTP 요청을 통한 텍스트 추출 (백업 방법)
  Future<String> _extractTextWithHttpRequest(File imageFile) async {
    try {
      // 서비스 계정 키 파일 로드
      final credentialsFile = await _loadCredentialsFile();
      final apiKey = credentialsFile['api_key'] as String?;

      if (apiKey == null) {
        throw Exception('API 키를 찾을 수 없습니다.');
      }

      // 이미지 파일을 base64로 인코딩
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // API 요청 생성
      final url = Uri.parse(
        'https://vision.googleapis.com/v1/images:annotate?key=$apiKey',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'requests': [
            {
              'image': {'content': base64Image},
              'features': [
                {'type': 'TEXT_DETECTION', 'maxResults': 50}
              ],
              'imageContext': {
                'languageHints': [_targetLanguage, 'en']
              }
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final responses = data['responses'] as List<dynamic>;

        if (responses.isNotEmpty &&
            responses[0]['textAnnotations'] != null &&
            (responses[0]['textAnnotations'] as List).isNotEmpty) {
          // 개별 텍스트 블록 처리 (첫 번째 항목은 전체 텍스트이므로 건너뜀)
          final textBlocks =
              (responses[0]['textAnnotations'] as List).skip(1).toList();

          // 필터링된 텍스트 블록을 저장할 리스트
          final filteredBlocks = [];

          for (final block in textBlocks) {
            final text = block['description'] as String? ?? '';

            // 텍스트가 비어있으면 건너뜀
            if (text.isEmpty) continue;

            // 필터링 조건 적용
            if (_shouldKeepTextBlock(text)) {
              filteredBlocks.add(block);
            }
          }

          // 필터링된 텍스트 블록이 없으면 빈 문자열 반환
          if (filteredBlocks.isEmpty) {
            debugPrint('HTTP 요청: 필터링 후 감지된 텍스트 블록이 없습니다.');
            return '';
          }

          // 필터링된 텍스트 블록을 위치에 따라 정렬하고 결합
          final combinedText = _combineHttpTextBlocks(filteredBlocks);
          debugPrint('HTTP 요청: 필터링 후 감지된 텍스트: $combinedText');
          return combinedText;
        }

        return '';
      } else {
        throw Exception('API 응답 오류: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('HTTP 요청으로 OCR 시도 중 오류 발생: $e');
      throw e;
    }
  }

  // HTTP 응답의 텍스트 블록을 위치에 따라 정렬하고 결합하는 메서드
  String _combineHttpTextBlocks(List<dynamic> blocks) {
    // 텍스트 블록을 위치(세로 방향)에 따라 정렬
    blocks.sort((a, b) {
      final aY = a['boundingPoly']?['vertices']?[0]?['y'] ?? 0;
      final bY = b['boundingPoly']?['vertices']?[0]?['y'] ?? 0;

      // Y 좌표가 같으면 X 좌표로 정렬 (왼쪽에서 오른쪽으로)
      if ((aY - bY).abs() < 10) {
        final aX = a['boundingPoly']?['vertices']?[0]?['x'] ?? 0;
        final bX = b['boundingPoly']?['vertices']?[0]?['x'] ?? 0;
        return aX.compareTo(bX);
      }

      return aY.compareTo(bY);
    });

    // 정렬된 블록을 결합
    final buffer = StringBuffer();
    int? lastY;

    for (final block in blocks) {
      final text = block['description'] as String? ?? '';
      final y = block['boundingPoly']?['vertices']?[0]?['y'] ?? 0;

      // 새로운 줄인지 확인 (Y 좌표가 이전 블록과 충분히 다른 경우)
      if (lastY != null && (y - lastY).abs() > 10) {
        buffer.write('\n');
      } else if (lastY != null) {
        // 같은 줄의 다른 블록이면 공백 추가
        buffer.write(' ');
      }

      buffer.write(text);
      lastY = y;
    }

    return buffer.toString();
  }

  // 리소스 해제
  void dispose() {
    // 필요한 경우 리소스 해제 로직 추가
  }
}
