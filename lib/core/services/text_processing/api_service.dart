import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';

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
      debugPrint('🌐 [API] 스트리밍 번역 시작: ${textSegments.length}개 세그먼트');
      if (processingMode != null) {
        debugPrint('📝 [API] 처리 모드: $processingMode');
      }
    }

    try {
      // Firebase Functions URL 직접 호출 (HTTP 스트리밍)
      final url = 'https://asia-southeast1-mylingowith.cloudfunctions.net/translateSegmentsStream';
      
      final authToken = await _getAuthToken();
      
      final request = http.Request('POST', Uri.parse(url));
      request.headers.addAll({
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      });
      final requestBody = {
        'textSegments': textSegments,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'needPinyin': needPinyin,
        'pageId': pageId,
        'noteId': noteId,
      };
      
      // 처리 모드 정보 추가
      if (processingMode != null) {
        requestBody['processingMode'] = processingMode;
        if (kDebugMode) {
          debugPrint('📄 [API] 처리 모드 전달: $processingMode');
        }
      }
      
      // 페이지별 세그먼트 정보가 있으면 추가
      if (pageSegments != null && pageSegments.isNotEmpty) {
        requestBody['pageSegments'] = pageSegments;
        if (kDebugMode) {
          debugPrint('📄 [API] 페이지별 처리: ${pageSegments.length}개 페이지');
        }
      }
      
      request.body = jsonEncode(requestBody);

      final client = http.Client();
      final response = await client.send(request);

      if (response.statusCode == 200) {
        if (kDebugMode) {
          debugPrint('✅ [API] HTTP 200 응답 수신 - 스트리밍 시작');
        }
        
        // 실시간 스트리밍 응답 처리
        await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (kDebugMode) {
            debugPrint('📡 [API] 원시 청크 수신: "$chunk"');
          }
          
          if (chunk.startsWith('data: ')) {
            final jsonStr = chunk.substring(6); // 'data: ' 제거
            if (jsonStr.trim().isNotEmpty) {
              if (kDebugMode) {
                debugPrint('📦 [API] JSON 데이터 파싱 시도: "$jsonStr"');
              }
              try {
                final chunkData = jsonDecode(jsonStr);
                
                if (kDebugMode) {
                  final chunkIndex = chunkData['chunkIndex'] + 1;
                  final totalChunks = chunkData['totalChunks'];
                  final isComplete = chunkData['isComplete'] == true;
                  debugPrint('📦 [API] 실시간 청크 수신: ${chunkIndex}/${totalChunks}, 완료: $isComplete');
                  
                  if (chunkData.containsKey('pageId')) {
                    debugPrint('📄 [API] 페이지 ID: ${chunkData['pageId']}');
                  }
                }
                
                yield chunkData;
                
                // 완료 신호 확인
                if (chunkData['isComplete'] == true) {
                  if (kDebugMode) {
                    debugPrint('✅ [API] 스트리밍 완료 신호 확인 - 루프 종료');
                  }
                  break;
                }
                
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('❌ [API] 청크 파싱 실패: $e');
                }
              }
            }
          }
        }
        
        if (kDebugMode) {
          debugPrint('🔚 [API] 스트리밍 루프 종료 - 연결 닫기');
        }
        client.close();
      } else {
        if (kDebugMode) {
          debugPrint('❌ [API] HTTP 오류: ${response.statusCode}');
          debugPrint('📄 [API] 응답 헤더: ${response.headers}');
        }
        client.close();
        throw Exception('스트리밍 요청 실패: ${response.statusCode}');
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [API] 스트리밍 오류: $e');
      }
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