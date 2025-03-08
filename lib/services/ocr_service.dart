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

  // 핀인 성조 기호 (1-4성)
  final List<String> _toneMarks = [
    'ā',
    'á',
    'ǎ',
    'à',
    'ē',
    'é',
    'ě',
    'è',
    'ī',
    'í',
    'ǐ',
    'ì',
    'ō',
    'ó',
    'ǒ',
    'ò',
    'ū',
    'ú',
    'ǔ',
    'ù',
    'ǖ',
    'ǘ',
    'ǚ',
    'ǜ'
  ];

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
        // 전체 텍스트 (첫 번째 항목)
        final fullText = annotations.textAnnotations![0].description ?? '';
        debugPrint('감지된 전체 텍스트: $fullText');

        // 핀인 제거 및 필터링 처리
        final processedText = _processExtractedText(fullText);

        // 개별 텍스트 블록 처리는 건너뛰고 전체 텍스트만 사용
        return processedText;
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

  // 추출된 전체 텍스트 처리 (핀인 제거 및 필터링)
  String _processExtractedText(String text) {
    // 문장 단위로 분리하여 처리
    final sentences = _splitIntoSentences(text);
    final processedSentences = <String>[];

    for (final sentence in sentences) {
      // 핀인 패턴 확인 (알파벳과 성조 기호로만 구성된 문장)
      if (_isPinyinLine(sentence)) {
        debugPrint('핀인으로 판단되어 제거: $sentence');
        continue;
      }

      // 중국어 문자가 포함된 문장만 유지
      if (_containsChineseOrValidCompound(sentence)) {
        // 문장 내에서 핀인 부분 제거 (문장 부호는 유지)
        final cleanedSentence = _removePinyin(sentence);
        if (cleanedSentence.trim().isNotEmpty) {
          processedSentences.add(cleanedSentence);
          debugPrint('처리된 문장: $cleanedSentence');
        }
      }
    }

    final result = processedSentences.join('\n');
    debugPrint('처리 후 텍스트 길이: ${result.length}');
    return result;
  }

  // 텍스트를 문장 단위로 분리
  List<String> _splitIntoSentences(String text) {
    if (text.isEmpty) return [];

    // 문장 구분자 패턴 (마침표, 느낌표, 물음표, 쉼표 등 뒤에 공백이 있을 수도 있음)
    final pattern = RegExp(r'(?<=[.!?。！？])\s*');

    // 문장 구분자로 분리
    final sentences = text.split(pattern);

    // 빈 문장 제거
    return sentences.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  // 핀인 줄인지 확인 (알파벳과 성조 기호로만 구성)
  bool _isPinyinLine(String line) {
    // 공백 제거
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;

    // 문장 부호만 있는 경우 핀인이 아님
    if (RegExp(r'^[。！？，,\.!?]+$').hasMatch(trimmed)) {
      return false;
    }

    // 중국어 문자가 포함되어 있으면 핀인이 아님
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed)) {
      return false;
    }

    // 성조 기호가 포함되어 있는지 확인
    bool hasToneMark = false;
    for (final mark in _toneMarks) {
      if (trimmed.contains(mark)) {
        hasToneMark = true;
        break;
      }
    }

    // 알파벳과 성조 기호, 공백만 포함되어 있는지 확인
    final nonPinyinChars = RegExp(r'[^a-zA-Z\s' + _toneMarks.join('') + ']');
    final containsNonPinyinChars = nonPinyinChars.hasMatch(trimmed);

    // 알파벳이 포함되어 있고, 성조 기호가 있거나 알파벳/공백만 있으면 핀인으로 간주
    return RegExp(r'[a-zA-Z]').hasMatch(trimmed) &&
        (hasToneMark || !containsNonPinyinChars);
  }

  // 텍스트에서 핀인 부분 제거
  String _removePinyin(String text) {
    // 줄 단위로 처리
    final lines = text.split('\n');
    final cleanedLines = <String>[];

    for (final line in lines) {
      // 핀인 줄이면 제거
      if (_isPinyinLine(line)) {
        continue;
      }

      // 단어 단위로 분리하여 핀인 단어 제거
      final words = line.split(' ');
      final cleanedWords = <String>[];

      for (final word in words) {
        // 문장 부호만 있는 경우 유지
        if (RegExp(r'^[。！？，,\.!?]+$').hasMatch(word.trim())) {
          cleanedWords.add(word);
          continue;
        }

        // 핀인 단어가 아니면 유지
        if (!_isPinyinWord(word)) {
          cleanedWords.add(word);
        } else {
          debugPrint('핀인으로 판단되어 제외: $word');
        }
      }

      final cleanedLine = cleanedWords.join(' ');
      if (cleanedLine.trim().isNotEmpty) {
        cleanedLines.add(cleanedLine);
      }
    }

    return cleanedLines.join('\n');
  }

  // 단어가 핀인인지 확인
  bool _isPinyinWord(String word) {
    // 공백 제거
    final trimmed = word.trim();
    if (trimmed.isEmpty) return false;

    // 문장 부호만 있는 경우 핀인이 아님
    if (RegExp(r'^[。！？，,\.!?]+$').hasMatch(trimmed)) {
      return false;
    }

    // 중국어 문자가 포함되어 있으면 핀인이 아님
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed)) {
      return false;
    }

    // 성조 기호가 포함되어 있는지 확인
    bool hasToneMark = false;
    for (final mark in _toneMarks) {
      if (trimmed.contains(mark)) {
        hasToneMark = true;
        break;
      }
    }

    // 알파벳과 성조 기호만 포함되어 있는지 확인
    final nonPinyinChars = RegExp(r'[^a-zA-Z' + _toneMarks.join('') + ']');
    final containsNonPinyinChars = nonPinyinChars.hasMatch(trimmed);

    // 알파벳이 포함되어 있고, 성조 기호가 있거나 알파벳만 있으면 핀인으로 간주
    return RegExp(r'[a-zA-Z]').hasMatch(trimmed) &&
        (hasToneMark || !containsNonPinyinChars);
  }

  // 중국어 문자 또는 유효한 복합문(영어+중국어, 숫자+중국어)이 포함되어 있는지 확인
  bool _containsChineseOrValidCompound(String text) {
    // 공백만 있는 경우 제외
    if (text.trim().isEmpty) return false;

    // 중국어 문자 포함 여부
    final hasChineseChars = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);

    // 영어 문자 포함 여부
    final hasEnglishChars = RegExp(r'[a-zA-Z]').hasMatch(text);

    // 문장 부호 포함 여부 (중국어 문장 부호 포함)
    final hasPunctuation = RegExp(r'[。！？，,\.!?]').hasMatch(text);

    // 숫자가 포함되어 있는지 확인
    final hasDigits = RegExp(r'\d').hasMatch(text);

    // 중국어가 포함된 경우 유지
    if (hasChineseChars) {
      return true;
    }

    // 영어+숫자 조합인 경우 유지 (예: "Chapter 1")
    if (hasEnglishChars && hasDigits) {
      return true;
    }

    // 문장 부호만 있는 경우 유지 (문장 구분을 위해)
    if (hasPunctuation && text.trim().length <= 2) {
      return true;
    }

    // 그 외의 경우 (한국어, 일본어 등) 제외
    if (!hasChineseChars && !hasEnglishChars && !hasPunctuation) {
      debugPrint('지원되지 않는 언어 텍스트 제외: $text');
      return false;
    }

    // 기본적으로 영어만 있는 경우도 유지 (영어+중국어 조합을 위해)
    return true;
  }

  // 텍스트 블록을 필터링하는 메서드
  bool _shouldKeepTextBlock(String text) {
    // 문장 부호만 있는 경우 유지
    if (RegExp(r'^[。！？，,\.!?:"]+$').hasMatch(text.trim())) {
      debugPrint('문장 부호 유지: $text');
      return true;
    }

    // 핀인으로 판단되면 제외
    if (_isPinyinWord(text) || _isPinyinLine(text)) {
      debugPrint('핀인으로 판단되어 제외: $text');
      return false;
    }

    // 1. 숫자만 있는 경우 제외 (페이지 번호로 간주)
    if (RegExp(r'^\d+$').hasMatch(text)) {
      debugPrint('숫자만 있는 텍스트 제외: $text');
      return false;
    }

    // 2. 중국어 문자가 포함되어 있는지 확인
    final hasChineseChars = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);

    // 3. 영어 문자가 포함되어 있는지 확인
    final hasEnglishChars = RegExp(r'[a-zA-Z]').hasMatch(text);

    // 4. 문장 부호가 포함되어 있는지 확인
    final hasPunctuation = RegExp(r'[。！？，,\.!?:"]').hasMatch(text);

    // 5. 숫자가 포함되어 있는지 확인
    final hasDigits = RegExp(r'\d').hasMatch(text);

    // 중국어가 포함된 경우 유지
    if (hasChineseChars) {
      return true;
    }

    // 영어+숫자 조합인 경우 유지 (예: "Chapter 1")
    if (hasEnglishChars && hasDigits) {
      return true;
    }

    // 문장 부호가 포함된 경우 유지
    if (hasPunctuation) {
      return true;
    }

    // 그 외의 경우 (한국어, 일본어 등) 제외
    if (!hasChineseChars && !hasEnglishChars && !hasPunctuation) {
      debugPrint('지원되지 않는 언어 텍스트 제외: $text');
      return false;
    }

    // 기본적으로 영어만 있는 경우도 유지 (영어+중국어 조합을 위해)
    return true;
  }

  // 텍스트 블록을 위치에 따라 정렬하고 결합하는 메서드
  String _combineTextBlocks(List<vision.EntityAnnotation> blocks) {
    if (blocks.isEmpty) return '';

    // 텍스트 블록을 Y 좌표에 따라 그룹화
    final Map<int, List<vision.EntityAnnotation>> lineGroups = {};

    // 각 블록의 Y 좌표 중앙값 계산
    for (final block in blocks) {
      if (block.boundingPoly == null || block.boundingPoly!.vertices == null)
        continue;

      // 바운딩 박스의 중앙 Y 좌표 계산
      final vertices = block.boundingPoly!.vertices!;
      if (vertices.length < 4) continue;

      // 상단 Y 좌표 (왼쪽 상단, 오른쪽 상단 점의 평균)
      final topY = ((vertices[0].y ?? 0) + (vertices[1].y ?? 0)) ~/ 2;

      // 10픽셀 단위로 반올림하여 같은 줄로 그룹화
      final lineKey = (topY ~/ 10) * 10;

      if (!lineGroups.containsKey(lineKey)) {
        lineGroups[lineKey] = [];
      }
      lineGroups[lineKey]!.add(block);
    }

    // 각 줄 내에서 X 좌표에 따라 정렬
    for (final lineKey in lineGroups.keys) {
      lineGroups[lineKey]!.sort((a, b) {
        final aX = a.boundingPoly?.vertices?[0].x ?? 0;
        final bX = b.boundingPoly?.vertices?[0].x ?? 0;
        return aX.compareTo(bX);
      });
    }

    // 줄 키를 기준으로 정렬 (위에서 아래로)
    final sortedLineKeys = lineGroups.keys.toList()..sort();

    // 정렬된 줄을 결합
    final buffer = StringBuffer();

    debugPrint('정렬된 줄 수: ${sortedLineKeys.length}');

    for (int i = 0; i < sortedLineKeys.length; i++) {
      final lineKey = sortedLineKeys[i];
      final lineBlocks = lineGroups[lineKey]!;

      debugPrint('줄 $i의 블록 수: ${lineBlocks.length}');

      // 현재 줄의 텍스트 블록 결합
      final lineBuffer = StringBuffer();
      for (int j = 0; j < lineBlocks.length; j++) {
        final text = lineBlocks[j].description ?? '';

        // 문장 부호만 있는 경우 공백 없이 추가
        final isPunctuation = RegExp(r'^[。！？，,\.!?:"]+$').hasMatch(text.trim());

        // 첫 번째 블록이 아니면 공백 추가
        if (j > 0 && !isPunctuation) lineBuffer.write(' ');

        lineBuffer.write(text);
      }

      debugPrint('줄 $i 텍스트: ${lineBuffer.toString()}');

      // 줄 추가
      if (i > 0) buffer.write('\n');
      buffer.write(lineBuffer.toString());
    }

    final result = buffer.toString();
    debugPrint('결합된 텍스트: $result');
    return result;
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
          // 전체 텍스트 (첫 번째 항목)
          final fullText =
              responses[0]['textAnnotations'][0]['description'] as String? ??
                  '';
          debugPrint('HTTP 요청: 감지된 전체 텍스트: $fullText');

          // 핀인 제거 및 필터링 처리
          final processedText = _processExtractedText(fullText);

          // 개별 텍스트 블록 처리는 건너뛰고 전체 텍스트만 사용
          return processedText;
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

  // 리소스 해제
  void dispose() {
    // 필요한 경우 리소스 해제 로직 추가
  }
}
