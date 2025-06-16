import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../models/text_unit.dart';
import '../../models/page_processing_data.dart';
import '../../models/processed_text.dart';
import 'api_service.dart';

/// **스트리밍 수신 & 분배 서비스**
/// 서버 HTTP 스트리밍을 받아서 페이지별로 분배하는 역할
/// - 네트워크 통신 (서버 ↔ 클라이언트)
/// - 청크 데이터 파싱 및 TextUnit 변환
/// - 다중 페이지 텍스트 유사도 분배
/// - 스트리밍 결과 조율

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

    final Map<String, List<TextUnit>> pageResults = {};
    int processedChunks = 0;

    // Differential Update를 위한 페이지별 OCR 세그먼트 준비
    final Map<String, List<String>> pageOcrSegments = {};
    final processingMode = pages.isNotEmpty ? pages.first.mode : TextProcessingMode.segment;
    
    // 페이지별 OCR 세그먼트 분리 저장
    for (final page in pages) {
      pageOcrSegments[page.pageId] = List.from(page.textSegments);
    }
    
    if (kDebugMode && processingMode == TextProcessingMode.segment) {
      debugPrint('🔄 [Differential Update] 활성화: 페이지별 OCR 세그먼트');
      for (final entry in pageOcrSegments.entries) {
        debugPrint('   📄 ${entry.key}: ${entry.value.length}개 세그먼트');
      }
    }

    bool hasReceivedAnyChunk = false;

    try {
      // 페이지별 세그먼트 정보 생성
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
        }

        // 오류 청크 처리
        if (chunkData['isError'] == true) {
                  yield StreamingReceiveResult.error(
            chunkIndex: chunkData['chunkIndex'] as int,
            error: chunkData['error']?.toString() ?? '알 수 없는 오류',
          );
          continue;
        }

        // 정상 청크 처리 (Differential Update 적용)
        final pageId = chunkData['pageId'] as String?;
        final pageSpecificSegments = pageId != null && pageOcrSegments.containsKey(pageId) 
            ? pageOcrSegments[pageId] 
            : null;
            
        // 세그먼트 모드에서 pageId가 없을 때 폴백 처리
        List<String>? finalOriginalSegments;
        if (processingMode == TextProcessingMode.segment) {
          if (pageSpecificSegments != null) {
            finalOriginalSegments = pageSpecificSegments;
          } else if (pageOcrSegments.isNotEmpty) {
            // 첫 번째 페이지의 세그먼트 사용 (폴백)
            finalOriginalSegments = pageOcrSegments.values.first;
            if (kDebugMode) {
              debugPrint('⚠️ [폴백] pageId 없음, 첫 번째 페이지 세그먼트 사용');
            }
          }
        }
            
        if (kDebugMode) {
          debugPrint('🔍 [OCR 세그먼트 전달] 분석:');
          debugPrint('   처리 모드: $processingMode');
          debugPrint('   서버 pageId: $pageId');
          debugPrint('   pageOcrSegments 키: ${pageOcrSegments.keys.toList()}');
          debugPrint('   pageSpecificSegments: ${pageSpecificSegments?.length ?? 0}개');
          debugPrint('   finalOriginalSegments: ${finalOriginalSegments?.length ?? 0}개');
          if (finalOriginalSegments != null) {
            debugPrint('   finalOriginalSegments 내용: ${finalOriginalSegments.map((s) => '"$s"').join(', ')}');
          }
        }
            
        final chunkUnits = _extractUnitsFromChunkData(
          chunkData,
          originalSegments: finalOriginalSegments,
        );
        final chunkIndex = chunkData['chunkIndex'] as int;
        
        if (kDebugMode) {
          debugPrint('📦 청크 ${chunkIndex} 처리: ${chunkUnits.length}개 유닛');
        }
        
        // 페이지 ID 기반 분배 (서버에서 제공)
        if (pageId != null) {
          pageResults.putIfAbsent(pageId, () => []);
          pageResults[pageId]!.addAll(chunkUnits);
          
          if (kDebugMode) {
            debugPrint('📄 서버 지정 페이지: $pageId (+${chunkUnits.length}개)');
          }
        } else {
          // 기존 방식 (페이지 ID 없는 경우)
        await _distributeUnitsToPages(
          chunkUnits, 
          pages, 
          pageResults,
          isFirstChunk: chunkIndex == 0,
        );
        }
        
        processedChunks++;
        
        // 완료 상태 확인
        final isComplete = chunkData['isComplete'] == true;
        
        if (kDebugMode) {
          debugPrint('📊 [스트리밍] 청크 상태: ${chunkIndex + 1}/${chunkData['totalChunks']}, 완료: $isComplete');
          debugPrint('📄 [스트리밍] 현재 페이지 결과: ${pageResults.keys.toList()}');
          for (final entry in pageResults.entries) {
            debugPrint('   - ${entry.key}: ${entry.value.length}개 유닛');
          }
        }
        
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
            debugPrint('✅ [스트리밍] 완료 신호 수신: ${processedChunks}개 청크');
            debugPrint('📊 [스트리밍] 최종 페이지 결과:');
            for (final entry in pageResults.entries) {
              debugPrint('   - ${entry.key}: ${entry.value.length}개 유닛');
            }
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

  /// LLM 결과를 페이지별로 순차적으로 분배
  /// 
  /// **새로운 로직:**
  /// - 텍스트 유사도 비교 제거
  /// - 순서대로 페이지별 누적
  /// - LLM이 재배치/병합한 결과를 그대로 반영
  Future<void> _distributeUnitsToPages(
    List<TextUnit> chunkUnits,
    List<PageProcessingData> pages,
    Map<String, List<TextUnit>> pageResults, {
    bool isFirstChunk = false,
  }) async {
    if (chunkUnits.isEmpty || pages.isEmpty) return;
    
    if (pages.length == 1) {
      // 단일 페이지: LLM 결과를 순차적으로 누적
      final pageId = pages.first.pageId;
      pageResults.putIfAbsent(pageId, () => []);
      pageResults[pageId]!.addAll(chunkUnits);
      
      if (kDebugMode) {
        debugPrint('✅ 단일 페이지 순차 누적: ${pageId} (+${chunkUnits.length}개, 총 ${pageResults[pageId]!.length}개)');
      }
    } else {
      // 다중 페이지: OCR 세그먼트 순서 기반 순차 분배
      await _distributeUnitsToMultiplePages(chunkUnits, pages, pageResults);
    }
  }

  /// 다중 페이지에 유닛 분배 (기준점 비교 방식)
  Future<void> _distributeUnitsToMultiplePages(
    List<TextUnit> chunkUnits,
    List<PageProcessingData> pages,
    Map<String, List<TextUnit>> pageResults,
  ) async {
    // 각 페이지의 기준점 생성 (첫 번째 + 마지막 세그먼트)
    final pageMarkers = <String, PageMarker>{};
    
    for (final page in pages) {
      if (page.textSegments.isNotEmpty) {
        pageMarkers[page.pageId] = PageMarker(
          pageId: page.pageId,
          firstSegment: page.textSegments.first,
          lastSegment: page.textSegments.last,
          totalSegments: page.textSegments.length,
        );
      }
    }
    
    if (kDebugMode) {
      debugPrint('📄 다중 페이지 분배 (기준점 방식): ${chunkUnits.length}개 LLM 유닛');
      for (final marker in pageMarkers.values) {
        debugPrint('   📄 ${marker.pageId}: "${marker.firstSegment}" ... "${marker.lastSegment}" (${marker.totalSegments}개)');
      }
    }
    
    // LLM 유닛을 기준점 비교로 페이지별 분배
      for (final unit in chunkUnits) {
      final assignedPageId = _findMatchingPage(unit, pageMarkers.values.toList());
      
      if (assignedPageId != null) {
        pageResults.putIfAbsent(assignedPageId, () => []);
        pageResults[assignedPageId]!.add(unit);
      } else {
        // 매칭되지 않는 경우 첫 번째 페이지에 할당 (폴백)
        final fallbackPageId = pages.first.pageId;
        pageResults.putIfAbsent(fallbackPageId, () => []);
        pageResults[fallbackPageId]!.add(unit);
        
        if (kDebugMode) {
          debugPrint('⚠️ 매칭 실패, 폴백 할당: "${unit.originalText}" → ${fallbackPageId}');
        }
        }
      }
      
      if (kDebugMode) {
      debugPrint('✅ 다중 페이지 분배 완료:');
      for (final entry in pageResults.entries) {
        debugPrint('   📄 ${entry.key}: ${entry.value.length}개 유닛');
      }
    }
  }

  /// LLM 유닛이 어느 페이지에 속하는지 찾기
  String? _findMatchingPage(TextUnit unit, List<PageMarker> pageMarkers) {
    final unitText = unit.originalText.trim();
    
    // 1. 정확한 포함 관계 확인 (첫 번째 또는 마지막 세그먼트와 일치)
    for (final marker in pageMarkers) {
      if (unitText.contains(marker.firstSegment.trim()) || 
          unitText.contains(marker.lastSegment.trim()) ||
          marker.firstSegment.trim().contains(unitText) ||
          marker.lastSegment.trim().contains(unitText)) {
        return marker.pageId;
      }
    }
    
    // 2. 부분 문자열 유사도 확인 (70% 이상 일치)
    double maxSimilarity = 0.0;
    String? bestMatchPageId;
    
    for (final marker in pageMarkers) {
      final firstSimilarity = _calculateSimilarity(unitText, marker.firstSegment.trim());
      final lastSimilarity = _calculateSimilarity(unitText, marker.lastSegment.trim());
      final maxPageSimilarity = math.max(firstSimilarity, lastSimilarity);
      
      if (maxPageSimilarity > maxSimilarity && maxPageSimilarity >= 0.7) {
        maxSimilarity = maxPageSimilarity;
        bestMatchPageId = marker.pageId;
      }
    }
    
    return bestMatchPageId;
  }

  /// 간단한 문자열 유사도 계산 (공통 문자 비율)
  double _calculateSimilarity(String text1, String text2) {
    if (text1.isEmpty || text2.isEmpty) return 0.0;
    
    final shorter = text1.length <= text2.length ? text1 : text2;
    final longer = text1.length > text2.length ? text1 : text2;
    
    int matchCount = 0;
    for (int i = 0; i < shorter.length; i++) {
      if (longer.contains(shorter[i])) {
        matchCount++;
      }
    }
    
    return matchCount / shorter.length;
  }
  
  /// 페이지별 세그먼트 정보 생성 (서버 전송용)
  List<Map<String, dynamic>>? _createPageSegments(List<PageProcessingData> pages) {
    if (pages.length <= 1) {
      // 단일 페이지인 경우 null 반환 (기존 방식 사용)
      return null;
    }
    
    return pages.map((page) => {
      'pageId': page.pageId,
      'segments': page.textSegments,
    }).toList();
  }

  /// 스트리밍 청크 데이터에서 TextUnit 리스트 추출 (Differential Update 최적화)
  List<TextUnit> _extractUnitsFromChunkData(
    Map<String, dynamic> chunkData, {
    List<String>? originalSegments, // OCR 원본 세그먼트 (differential update용)
  }) {
    try {
      if (chunkData['units'] == null) return [];

      final units = chunkData['units'] as List;
      
      if (kDebugMode) {
        debugPrint('📦 [청크 데이터 추출] 시작');
        debugPrint('   유닛 개수: ${units.length}');
        debugPrint('   OCR 세그먼트: ${originalSegments?.length ?? 0}개');
        if (originalSegments != null && originalSegments.isNotEmpty) {
          debugPrint('   OCR 세그먼트 샘플: "${originalSegments.first}"');
        }
      }
      
      // Differential Update 방식인지 확인 (서버 응답 기반)
      if (originalSegments != null && _isDifferentialUpdate(units, chunkData)) {
        if (kDebugMode) {
          debugPrint('✅ [Differential Update] 모드 선택됨');
        }
        return _buildUnitsFromDifferentialUpdate(units, originalSegments);
      }
      
      // 기존 방식: 서버에서 모든 데이터 포함 (호환성)
      if (kDebugMode) {
        debugPrint('✅ [기존 방식] 모드 선택됨');
      }
      return _buildUnitsFromFullData(units);
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 청크 데이터 파싱 실패: $e');
        debugPrint('   청크 구조: ${chunkData.keys}');
      }
      return [];
    }
  }

  /// Differential Update 방식인지 확인 (서버 응답 기반)
  bool _isDifferentialUpdate(List units, Map<String, dynamic> chunkData) {
    if (units.isEmpty) return false;
    
    if (kDebugMode) {
      debugPrint('🔍 [Differential Update 감지] 시작');
      debugPrint('   청크 데이터 키: ${chunkData.keys.toList()}');
      debugPrint('   첫 번째 유닛 키: ${units.first.keys.toList()}');
    }
    
    // 1. 서버에서 명시적으로 모드를 알려주는 경우
    final serverMode = chunkData['mode'] as String?;
    if (kDebugMode) {
      debugPrint('   서버 모드: $serverMode');
    }
    
    if (serverMode == 'differential') {
      if (kDebugMode) {
        debugPrint('🔄 [서버 지정] Differential Update 모드');
      }
      return true;
    }
    if (serverMode == 'full') {
      if (kDebugMode) {
        debugPrint('🔄 [서버 지정] Full Data 모드');
      }
      return false;
    }
    
    // 2. 클라이언트에서 추론 (기존 로직)
    final firstUnit = units.first;
    final hasIndex = firstUnit['index'] != null;
    final hasOriginal = firstUnit['original'] != null || firstUnit['originalText'] != null;
    
    if (kDebugMode) {
      debugPrint('   첫 번째 유닛 분석:');
      debugPrint('     index: ${firstUnit['index']}');
      debugPrint('     original: ${firstUnit['original']}');
      debugPrint('     originalText: ${firstUnit['originalText']}');
      debugPrint('     translation: ${firstUnit['translation']}');
      debugPrint('     hasIndex: $hasIndex');
      debugPrint('     hasOriginal: $hasOriginal');
    }
    
    final isDifferential = hasIndex && !hasOriginal;
    
    if (kDebugMode) {
      debugPrint('🔍 [클라이언트 추론] Differential Update: $isDifferential');
      debugPrint('   인덱스 존재: $hasIndex, 원문 존재: $hasOriginal');
    }
    
    return isDifferential;
  }

  /// Differential Update 방식으로 TextUnit 생성
  List<TextUnit> _buildUnitsFromDifferentialUpdate(
    List units, 
    List<String> originalSegments,
  ) {
    final textUnits = <TextUnit>[];
    
    if (kDebugMode) {
      debugPrint('🔄 [Differential Update] 인덱스 기반 매핑 시작');
      debugPrint('   서버 업데이트: ${units.length}개');
      debugPrint('   OCR 세그먼트: ${originalSegments.length}개');
      debugPrint('   OCR 세그먼트 전체: ${originalSegments.map((s) => '"$s"').join(', ')}');
    }
    
    for (int i = 0; i < units.length; i++) {
      final unitData = units[i];
      final index = unitData['index'] as int?;
      
      if (kDebugMode) {
        debugPrint('📦 [매핑 $i] 처리 중:');
        debugPrint('   LLM 인덱스: $index');
        debugPrint('   LLM 번역: "${unitData['translation']}"');
        debugPrint('   LLM 병음: "${unitData['pinyin']}"');
      }
      
      if (index == null || index < 0 || index >= originalSegments.length) {
        if (kDebugMode) {
          debugPrint('⚠️ 잘못된 인덱스: $index (범위: 0-${originalSegments.length - 1})');
        }
        continue;
      }
      
      final originalText = originalSegments[index];
      
      if (kDebugMode) {
        debugPrint('   OCR 원문[${index}]: "$originalText"');
      }
      
      // OCR 원본 세그먼트 + 서버 번역/병음
      final textUnit = TextUnit(
        originalText: originalText, // ✅ 기존 OCR 데이터 사용
        translatedText: unitData['translation'] ?? unitData['translatedText'] ?? '',
        pinyin: unitData['pinyin'] ?? '',
        sourceLanguage: unitData['sourceLanguage'] ?? 'zh-CN',
        targetLanguage: unitData['targetLanguage'] ?? 'ko',
        segmentType: _parseSegmentType(unitData['type'] ?? unitData['segmentType']),
      );
      
      if (kDebugMode) {
        debugPrint('✅ [매핑 완료] TextUnit 생성:');
        debugPrint('   원문: "${textUnit.originalText}"');
        debugPrint('   번역: "${textUnit.translatedText}"');
        debugPrint('   병음: "${textUnit.pinyin}"');
      }
      
      textUnits.add(textUnit);
    }
    
    if (kDebugMode) {
      debugPrint('✅ [Differential Update] 완료: ${textUnits.length}개 유닛 생성');
      debugPrint('   대역폭 절약: 원문 ${originalSegments.join('').length}자 전송 생략');
      debugPrint('   최종 결과 요약:');
      for (int i = 0; i < textUnits.length; i++) {
        final unit = textUnits[i];
        debugPrint('     [$i] "${unit.originalText}" → "${unit.translatedText}"');
      }
    }
    
    return textUnits;
  }

  /// 기존 방식으로 TextUnit 생성 (호환성)
  List<TextUnit> _buildUnitsFromFullData(List units) {
    if (kDebugMode) {
      debugPrint('🔄 [기존 방식] 전체 데이터 파싱');
    }
    
    return units.map<TextUnit>((unitData) {
      // 서버 응답 필드명 그대로 사용 (original, translation, pinyin)
      final original = unitData['original'] ?? unitData['originalText'] ?? '';
      final translation = unitData['translation'] ?? unitData['translatedText'] ?? '';
      final pinyin = unitData['pinyin'] ?? '';
      
      return TextUnit(
        originalText: original,
        translatedText: translation,
        pinyin: pinyin,
        sourceLanguage: unitData['sourceLanguage'] ?? 'zh-CN',
        targetLanguage: unitData['targetLanguage'] ?? 'ko',
        segmentType: _parseSegmentType(unitData['type'] ?? unitData['segmentType']),
      );
    }).toList();
  }

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

  /// 문자열에서 SegmentType 파싱
  SegmentType _parseSegmentType(String? typeString) {
    if (typeString == null) return SegmentType.unknown;
    
    try {
      return SegmentType.values.firstWhere(
        (e) => e.name == typeString.toLowerCase()
      );
    } catch (e) {
      return SegmentType.unknown;
    }
  }
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