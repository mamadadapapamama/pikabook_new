import 'dart:async';
// dart:math 제거됨 - 복잡한 유사도 계산 로직 제거
import 'package:flutter/foundation.dart';
import '../../models/text_unit.dart';
import '../../models/page_processing_data.dart';
import '../../models/processed_text.dart';
import 'api_service.dart';

/// **스트리밍 수신 서비스 (단순화됨)**
/// 서버 HTTP 스트리밍을 받아서 직접 전달하는 역할
/// - 네트워크 통신 (서버 ↔ 클라이언트)
/// - 서버 응답 직접 사용 (변환 로직 제거)
/// - 단순한 에러 처리

class StreamingReceiveService {
  final ApiService _apiService = ApiService();

  /// 스트리밍 번역 실행 및 결과 분배
  Stream<StreamingReceiveResult> processStreamingTranslation({
    required List<String> textSegments,
    required List<PageProcessingData> pages,
    required String sourceLanguage,
    required String targetLanguage,
    required String noteId,
    required bool needPinyin,
  }) async* {
    if (kDebugMode) {
      debugPrint('🌊 [스트리밍] 번역 시작: ${textSegments.length}개 세그먼트');
    }

    // 결과 추적
    final Map<String, List<TextUnit>> pageResults = {};
    int processedChunks = 0;
    
    // 폴백 처리용 페이지 정보만 유지 (단순화)
    final Map<String, List<String>> pageOcrSegments = {};
    for (final page in pages) {
      pageOcrSegments[page.pageId] = List.from(page.textSegments);
    }

    bool hasReceivedAnyChunk = false;

    try {
      // 서버 전송용 페이지 정보 (단순화됨)
      final pageSegments = _createPageSegments(pages);
      
      if (kDebugMode) {
        debugPrint('🚀 [스트리밍] API 스트림 시작 - 첫 번째 청크 대기 중...');
      }
      
      // HTTP 스트리밍 시작
      await for (final chunkData in _apiService.translateSegmentsStream(
        textSegments: textSegments,
        pageSegments: pageSegments,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        needPinyin: needPinyin,
        noteId: noteId,
        processingMode: pages.isNotEmpty ? pages.first.mode.toString() : null,
      )) {
        if (!hasReceivedAnyChunk) {
          hasReceivedAnyChunk = true;
          if (kDebugMode) {
            debugPrint('🎉 [스트리밍] 첫 번째 청크 수신 성공!');
          }
        }
        
        if (kDebugMode) {
          debugPrint('📦 [스트리밍] 청크 수신: ${chunkData['chunkIndex'] + 1}/${chunkData['totalChunks']}');
          debugPrint('🔍 [서버 응답] 전체 chunkData 키: ${chunkData.keys}');
          if (chunkData['units'] != null) {
            final units = chunkData['units'] as List;
            if (units.isNotEmpty) {
              final firstUnit = units.first as Map<String, dynamic>;
              debugPrint('🔍 [서버 응답] 첫 번째 유닛 키: ${firstUnit.keys}');
              debugPrint('🔍 [서버 응답] 첫 번째 유닛 데이터:');
              firstUnit.forEach((key, value) {
                debugPrint('   $key: $value');
              });
            }
          }
        }

        // 오류 청크 처리
        if (chunkData['isError'] == true) {
                  yield StreamingReceiveResult.error(
            chunkIndex: chunkData['chunkIndex'] as int,
            error: chunkData['error']?.toString() ?? '알 수 없는 오류',
          );
          continue;
        }

        // ✅ 단순화: 서버가 이미 완성된 데이터를 보내므로 직접 사용
        final pageId = chunkData['pageId'] as String?;
        final chunkIndex = chunkData['chunkIndex'] as int;
        
        // 서버에서 이미 완성된 TextUnit 배열을 직접 추출 (OCR 원본 텍스트와 매핑)
        final chunkUnits = _extractUnitsDirectly(chunkData, textSegments);
        
        if (kDebugMode && chunkUnits.isNotEmpty) {
          final firstUnit = chunkUnits.first;
          debugPrint('🔍 추출된 첫 번째 유닛:');
          debugPrint('   원문: "${firstUnit.originalText}"');
          debugPrint('   번역: "${firstUnit.translatedText}"');
          debugPrint('   병음: "${firstUnit.pinyin}"');
          debugPrint('   타입: ${firstUnit.segmentType}');
        }
        
        if (kDebugMode) {
          debugPrint('📦 청크 ${chunkIndex + 1} 처리: ${chunkUnits.length}개 유닛 (pageId: $pageId)');
        }
        
        // 서버가 제공한 pageId로 직접 분배 (복잡한 로직 제거)
        if (pageId != null) {
          pageResults.putIfAbsent(pageId, () => []);
          pageResults[pageId]!.addAll(chunkUnits);
        } else if (pages.isNotEmpty) {
          // pageId가 없는 경우 첫 번째 페이지에 할당 (폴백)
          final firstPageId = pages.first.pageId;
          pageResults.putIfAbsent(firstPageId, () => []);
          pageResults[firstPageId]!.addAll(chunkUnits);
        }
        
        processedChunks++;
        
        // 완료 상태 확인
        final isComplete = chunkData['isComplete'] == true;
        
        // 스트리밍 결과 반환
        yield StreamingReceiveResult.success(
          chunkIndex: chunkIndex,
          chunkUnits: chunkUnits,
          pageResults: Map.from(pageResults),
          isComplete: isComplete,
          processedChunks: processedChunks,
        );
        
        // 완료 확인
        if (isComplete) {
          if (kDebugMode) {
            debugPrint('✅ [스트리밍] 완료: $processedChunks개 청크, ${pageResults.length}개 페이지');
          }
          break;
        }
      }
      
      // 스트리밍이 전혀 시작되지 않은 경우 감지
      if (!hasReceivedAnyChunk) {
        if (kDebugMode) {
          debugPrint('⚠️ [스트리밍] 청크를 전혀 받지 못함 - 연결 문제 의심');
        }
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [스트리밍] 실패: $e');
        debugPrint('📊 [스트리밍] 수신된 청크 수: ${hasReceivedAnyChunk ? "1개 이상" : "0개"}');
      }
      
      // 폴백 처리
      yield* _createFallbackResults(pageOcrSegments, pages, sourceLanguage, targetLanguage);
    }
  }

  // ✅ 복잡한 분배 로직 제거됨 - 서버가 이미 pageId를 제공하므로 불필요
  
  /// 페이지별 세그먼트 정보 생성 (서버 전송용)
  List<Map<String, dynamic>>? _createPageSegments(List<PageProcessingData> pages) {
    if (pages.isEmpty) return null;

    if (kDebugMode) {
      debugPrint('📄 [스트리밍] 페이지별 세그먼트 정보 생성 (모든 모드)');
      debugPrint('   페이지 수: ${pages.length}개');
    }

    // 모든 페이지 정보를 서버의 '다중 페이지' 로직에 맞게 변환
    final pageSegments = pages.map((page) {
      final pageMap = <String, dynamic>{
        'pageId': page.pageId,
        'mode': page.mode.toString(),
      };

      if (page.mode == TextProcessingMode.paragraph) {
        // 문단 모드: 전체 텍스트를 'segments' 배열의 단일 원소로 감싸서 전달
        // 서버의 다중 페이지 로직이 page.segments 필드를 사용하기 때문
        pageMap['segments'] = [page.reorderedText];
        if (kDebugMode) {
          debugPrint('   📄 ${page.pageId} (paragraph): reorderedText를 segments 배열로 변환');
        }
      } else {
        // 문장 모드: 기존과 동일하게 segments 배열 전달
        pageMap['segments'] = page.textSegments;
        if (kDebugMode) {
          debugPrint('   📄 ${page.pageId} (segment): ${page.textSegments.length}개 세그먼트');
        }
      }
      return pageMap;
    }).toList();

    if (kDebugMode) {
      debugPrint('📤 [스트리밍] 서버 전송 데이터 준비 완료: ${pageSegments.length}개 페이지');
    }

    return pageSegments;
  }

  /// ✅ 단순화: 서버 응답에서 TextUnit 직접 추출 (변환 로직 제거)
  List<TextUnit> _extractUnitsDirectly(Map<String, dynamic> chunkData, List<String> textSegments) {
    try {
      final units = chunkData['units'] as List?;
      if (units == null || units.isEmpty) {
        return [];
      }

      // 서버 응답 필드를 클라이언트 형식으로 변환
      return units.map((unitData) {
        final serverUnit = Map<String, dynamic>.from(unitData as Map);
        
        // 서버의 index를 사용해서 원본 텍스트 매핑
        final index = serverUnit['index'] as int? ?? 0;
        final originalText = (index < textSegments.length) ? textSegments[index] : '';
        
        // 서버 필드명 -> 클라이언트 필드명 매핑
        final clientUnit = <String, dynamic>{
          'originalText': originalText, // OCR 텍스트 세그먼트에서 가져오기
          'translatedText': serverUnit['translation'], // translation -> translatedText
          'pinyin': serverUnit['pinyin'],
          'sourceLanguage': serverUnit['sourceLanguage'] ?? 'zh-CN',
          'targetLanguage': serverUnit['targetLanguage'] ?? 'ko',
          'segmentType': 'sentence', // 기본값으로 sentence 설정
        };
        
        return TextUnit.fromJson(clientUnit);
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TextUnit 직접 추출 실패: $e');
      }
      return [];
    }
  }

  // ✅ 복잡한 추출 로직 제거됨 - _extractUnitsDirectly()로 대체

  // ✅ 복잡한 Differential Update 로직 제거됨 - 서버가 이미 완성된 데이터 제공

  /// 스트리밍 실패 시 폴백 결과 생성
  Stream<StreamingReceiveResult> _createFallbackResults(
    Map<String, List<String>> pageOcrSegments,
    List<PageProcessingData> pages,
    String sourceLanguage,
    String targetLanguage,
  ) async* {
    final Map<String, List<TextUnit>> pageResults = {};
    
    // 폴백 텍스트 유닛 생성
    for (final pageId in pageOcrSegments.keys) {
      pageResults.putIfAbsent(pageId, () => []);
      
      for (final text in pageOcrSegments[pageId]!) {
      pageResults[pageId]!.add(TextUnit(
          originalText: text,
        translatedText: '[스트리밍 실패]',
        pinyin: '',
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      ));
      }
    }
    
    yield StreamingReceiveResult.success(
      chunkIndex: 0,
      chunkUnits: pageResults.values.expand((units) => units).toList(),
      pageResults: pageResults,
      isComplete: true,
      processedChunks: pageOcrSegments.length,
    );
  }

  // ✅ _parseSegmentType 제거됨 - 서버에서 이미 완성된 데이터 제공
}

/// 페이지 기준점 (첫 번째/마지막 세그먼트)
class PageMarker {
  final String pageId;
  final String firstSegment;
  final String lastSegment;
  final int totalSegments;

  PageMarker({
    required this.pageId,
    required this.firstSegment,
    required this.lastSegment,
    required this.totalSegments,
  });
}

/// 스트리밍 수신 결과
class StreamingReceiveResult {
  final bool isSuccess;
  final int chunkIndex;
  final List<TextUnit> chunkUnits;
  final Map<String, List<TextUnit>> pageResults;
  final bool isComplete;
  final int processedChunks;
  final String? error;

  StreamingReceiveResult._({
    required this.isSuccess,
    required this.chunkIndex,
    required this.chunkUnits,
    required this.pageResults,
    required this.isComplete,
    required this.processedChunks,
    this.error,
  });

  factory StreamingReceiveResult.success({
    required int chunkIndex,
    required List<TextUnit> chunkUnits,
    required Map<String, List<TextUnit>> pageResults,
    required bool isComplete,
    required int processedChunks,
  }) {
    return StreamingReceiveResult._(
      isSuccess: true,
      chunkIndex: chunkIndex,
      chunkUnits: chunkUnits,
      pageResults: pageResults,
      isComplete: isComplete,
      processedChunks: processedChunks,
    );
  }

  factory StreamingReceiveResult.error({
    required int chunkIndex,
    required String error,
  }) {
    return StreamingReceiveResult._(
      isSuccess: false,
      chunkIndex: chunkIndex,
      chunkUnits: [],
      pageResults: {},
      isComplete: false,
      processedChunks: 0,
      error: error,
    );
  }
} 