import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

/// 병렬 처리 유틸리티
class ParallelProcessor {
  /// 여러 작업을 병렬로 실행 (최대 동시 실행 수 제한)
  static Future<List<T>> runInParallel<T>(
    List<Future<T> Function()> tasks, {
    int maxConcurrency = 3,
  }) async {
    if (tasks.isEmpty) return [];
    
    final results = <T>[];
    final futures = <Future<T>>[];
    
    // 병렬 실행할 작업들을 청크로 나누기
    for (int i = 0; i < tasks.length; i += maxConcurrency) {
      final chunk = tasks.skip(i).take(maxConcurrency).toList();
      final chunkFutures = chunk.map((task) => task()).toList();
      
      // 현재 청크의 모든 작업 완료 대기
      final chunkResults = await Future.wait(chunkFutures);
      results.addAll(chunkResults);
      
      if (kDebugMode) {
        debugPrint('🔄 병렬 처리 진행: ${results.length}/${tasks.length}');
      }
    }
    
    return results;
  }

  /// 이미지 업로드를 병렬로 처리
  static Future<List<String>> uploadImagesInParallel(
    List<Future<String> Function()> uploadTasks, {
    int maxConcurrency = 2, // 네트워크 부하 고려
  }) async {
    return await runInParallel(uploadTasks, maxConcurrency: maxConcurrency);
  }

  /// OCR 처리를 병렬로 실행
  static Future<List<String>> processOcrInParallel(
    List<Future<String> Function()> ocrTasks, {
    int maxConcurrency = 3, // CPU 집약적 작업
  }) async {
    return await runInParallel(ocrTasks, maxConcurrency: maxConcurrency);
  }

  /// 타임아웃이 있는 병렬 처리
  static Future<List<T?>> runInParallelWithTimeout<T>(
    List<Future<T> Function()> tasks, {
    int maxConcurrency = 3,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final results = <T?>[];
    
    for (int i = 0; i < tasks.length; i += maxConcurrency) {
      final chunk = tasks.skip(i).take(maxConcurrency).toList();
      final chunkFutures = chunk.map((task) => 
        task().timeout(timeout).catchError((_) => null)
      ).toList();
      
      final chunkResults = await Future.wait(chunkFutures);
      results.addAll(chunkResults);
    }
    
    return results;
  }
} 