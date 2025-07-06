import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  // 성능 통계 저장
  final Map<String, int> _performanceStats = {
    'totalCalls': 0,
    'totalTime': 0,
    'averageTime': 0,
    'fastestCall': 999999,
    'slowestCall': 0,
  };

  Map<String, int> get performanceStats => Map.from(_performanceStats);

  /// 텍스트 세그먼트들을 서버에서 번역 (기존 배치 방식)
  Future<Map<String, dynamic>> translateSegments({
    required List<String> textSegments,
    String sourceLanguage = 'zh-CN',
    String targetLanguage = 'ko',
    bool needPinyin = true,
    String? pageId,
    String? noteId,
  }) async {
    final apiStartTime = DateTime.now();
    
    try {
      if (kDebugMode) {
        debugPrint('🌐 [API] 번역 시작: ${textSegments.length}개 세그먼트');
        debugPrint('📊 [API] 시작 시간: ${apiStartTime.millisecondsSinceEpoch}ms');
      }

      final callable = _functions.httpsCallable(
        'translateSegments',
        options: HttpsCallableOptions(
          timeout: const Duration(minutes: 8), // 8분으로 증가
        ),
      );
      
      final callStartTime = DateTime.now();
      final result = await callable.call({
        'textSegments': textSegments,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'needPinyin': needPinyin,
        'pageId': pageId,
        'noteId': noteId,
      });
      final callEndTime = DateTime.now();

      final apiTotalTime = callEndTime.difference(apiStartTime).inMilliseconds;
      final networkTime = callEndTime.difference(callStartTime).inMilliseconds;

      // 성능 통계 업데이트
      _updatePerformanceStats(apiTotalTime);

      if (kDebugMode) {
        debugPrint('✅ [API] 번역 완료');
        debugPrint('⏱️ [API] 총 소요시간: ${apiTotalTime}ms');
        debugPrint('🌐 [API] 네트워크 시간: ${networkTime}ms');
        debugPrint('🔧 [API] 오버헤드: ${apiTotalTime - networkTime}ms');
        debugPrint('📈 [API] 평균 응답시간: ${_performanceStats['averageTime']}ms');
        
        // 서버에서 반환한 통계 정보도 출력
        final data = Map<String, dynamic>.from(result.data);
        if (data['statistics'] != null) {
          final stats = Map<String, dynamic>.from(data['statistics']);
          debugPrint('🤖 [서버] 처리시간: ${stats['processingTime']}ms');
          debugPrint('📝 [서버] 세그먼트: ${stats['segmentCount']}개');
          debugPrint('📄 [서버] 문자수: ${stats['totalCharacters']}자');
        }
      }

      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      final apiErrorTime = DateTime.now().difference(apiStartTime).inMilliseconds;
      
      if (kDebugMode) {
        debugPrint('❌ [API] 호출 실패: $e');
        debugPrint('⏱️ [API] 실패까지 소요시간: ${apiErrorTime}ms');
      }
      rethrow;
    }
  }

  /// 텍스트 세그먼트들을 서버에서 실시간 스트리밍 번역
  Stream<Map<String, dynamic>> translateSegmentsStream({
    required List<String> textSegments,
    List<Map<String, dynamic>>? pageSegments, // 페이지별 세그먼트 정보 추가
    String sourceLanguage = 'zh-CN',
    String targetLanguage = 'ko',
    bool needPinyin = true,
    String? pageId,
    String? noteId,
    String? processingMode, // 처리 모드 추가
  }) async* {
    if (kDebugMode) {
      print('🌐 [API] 스트리밍 번역 시작: ${textSegments.length}개 세그먼트');
      if (processingMode != null) {
        print('📝 [API] 처리 모드: $processingMode');
      }
      if (pageSegments != null) {
        print('📄 [API] 페이지별 처리: ${pageSegments.length}개 페이지');
        for (final pageSegment in pageSegments) {
          print('   - ${pageSegment['pageId']}: ${pageSegment['mode']}');
          if (pageSegment['mode'] == 'TextProcessingMode.paragraph') {
            final textLength = pageSegment['reorderedText']?.toString().length ?? 0;
            print('     → 문단모드 텍스트: ${textLength}자');
          }
        }
      }
    }

    try {
      // Firebase Functions URL 직접 호출 (HTTP 스트리밍)
      final url = 'https://asia-southeast1-mylingowith.cloudfunctions.net/translateSegmentsStream';
      
      print('🔍 [API] Auth 토큰 가져오기 시작...');
      final authToken = await _getAuthToken();
      
      if (authToken != null) {
        print('✅ [API] Auth 토큰 획득 성공 (길이: ${authToken.length})');
      } else {
        print('⚠️ [API] Auth 토큰이 null입니다!');
      }
      
      final request = http.Request('POST', Uri.parse(url));
      request.headers.addAll({
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      });
      
      final requestBody = <String, dynamic>{
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'needPinyin': needPinyin,
        if (noteId != null) 'noteId': noteId,
        if (processingMode != null) 'processingMode': processingMode,
      };

      // 세그먼트 모드일 때만 textSegments 추가
      if (textSegments.isNotEmpty) {
        requestBody['textSegments'] = textSegments;
      }

      if (pageSegments != null && pageSegments.isNotEmpty) {
        requestBody['pageSegments'] = pageSegments;
        print('📄 [API] 페이지별 처리 정보 전달: ${pageSegments.length}개 페이지');
      }
      
      request.body = jsonEncode(requestBody);

      print('📤 [API] 서버 요청 전송 시작');
      print('   URL: $url');
      final prettyJson = const JsonEncoder.withIndent('  ').convert(requestBody);
      print('   Body: $prettyJson');

      final client = http.Client();
      
      print('🚀 [API] HTTP 요청 전송 중...');
      final response = await client.send(request);
      print('📡 [API] HTTP 응답 수신: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('✅ [API] HTTP 200 응답 수신 - 스트리밍 시작');
        
        bool hasReceivedAnyData = false;
        int chunkCount = 0;
        
        // 실시간 스트리밍 응답 처리
        await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (!hasReceivedAnyData) {
            hasReceivedAnyData = true;
            print('🎉 [API] 첫 번째 스트림 데이터 수신 성공!');
          }
          
          chunkCount++;
          
          if (kDebugMode) {
            print('📡 [API] 원시 청크 #$chunkCount 수신: "${chunk.substring(0, math.min(100, chunk.length))}${chunk.length > 100 ? '...' : ''}"');
          }
          
          if (chunk.startsWith('data: ')) {
            final jsonStr = chunk.substring(6); // 'data: ' 제거
            if (jsonStr.trim().isNotEmpty) {
              print('📦 [API] JSON 데이터 파싱 시도 #$chunkCount');
              try {
                final chunkData = jsonDecode(jsonStr);
                
                final chunkIndex = chunkData['chunkIndex'] + 1;
                final totalChunks = chunkData['totalChunks'];
                final isComplete = chunkData['isComplete'] == true;
                print('📦 [API] 실시간 청크 수신: ${chunkIndex}/${totalChunks}, 완료: $isComplete');
                
                if (chunkData.containsKey('pageId')) {
                  print('📄 [API] 페이지 ID: ${chunkData['pageId']}');
                }
                
                yield chunkData;
                
                // 완료 신호 확인
                if (chunkData['isComplete'] == true) {
                  print('✅ [API] 스트리밍 완료 신호 확인 - 루프 종료');
                  break;
                }
                
              } catch (e) {
                print('❌ [API] 청크 파싱 실패 #$chunkCount: $e');
                print('   원본 JSON: "$jsonStr"');
              }
            }
          }
        }
        
        print('🔚 [API] 스트리밍 루프 종료 - 연결 닫기');
        print('📊 [API] 총 수신 청크: $chunkCount개');
        
        if (!hasReceivedAnyData) {
          print('⚠️ [API] 스트림에서 데이터를 전혀 받지 못했습니다!');
        }
        
        client.close();
      } else {
        print('❌ [API] HTTP 오류: ${response.statusCode}');
        print('📄 [API] 응답 헤더: ${response.headers}');
        
        // 에러 응답 본문 읽기
        try {
          final errorBody = await response.stream.bytesToString();
          print('📄 [API] 에러 응답 본문: $errorBody');
        } catch (e) {
          print('⚠️ [API] 에러 응답 본문 읽기 실패: $e');
        }
        
        client.close();
        throw Exception('스트리밍 요청 실패: ${response.statusCode}');
      }

    } catch (e, stackTrace) {
      print('❌ [API] 스트리밍 오류: $e');
      print('📍 [API] 스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  /// Firebase Auth 토큰 가져오기
  Future<String?> _getAuthToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return await user?.getIdToken();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Auth 토큰 가져오기 실패: $e');
      }
      return null;
    }
  }

  void _updatePerformanceStats(int responseTime) {
    _performanceStats['totalCalls'] = _performanceStats['totalCalls']! + 1;
    _performanceStats['totalTime'] = _performanceStats['totalTime']! + responseTime;
    _performanceStats['averageTime'] = _performanceStats['totalTime']! ~/ _performanceStats['totalCalls']!;
    
    if (responseTime < _performanceStats['fastestCall']!) {
      _performanceStats['fastestCall'] = responseTime;
    }
    if (responseTime > _performanceStats['slowestCall']!) {
      _performanceStats['slowestCall'] = responseTime;
    }
  }

  void resetPerformanceStats() {
    _performanceStats['totalCalls'] = 0;
    _performanceStats['totalTime'] = 0;
    _performanceStats['averageTime'] = 0;
    _performanceStats['fastestCall'] = 999999;
    _performanceStats['slowestCall'] = 0;
  }
}