import 'dart:typed_data';

/// 캐시 저장소 인터페이스
/// 로컬 및 원격 저장소의 공통 인터페이스를 정의합니다.
abstract class CacheStorage<T> {
  /// 캐시에서 데이터 조회
  Future<T?> get(String key);
  
  /// 캐시에 데이터 저장
  Future<void> set(String key, T value, {Duration? ttl});
  
  /// 캐시에서 데이터 삭제
  Future<void> delete(String key);
  
  /// 특정 패턴의 키들 삭제
  Future<void> deleteByPattern(String pattern);
  
  /// 전체 캐시 삭제
  Future<void> clear();
  
  /// 모든 캐시 키 조회
  Future<List<String>> getKeys();
  
  /// 캐시 크기 조회 (바이트)
  Future<int> getSize();
  
  /// 캐시 항목 수 조회
  Future<int> getItemCount();
  
  /// 만료된 항목들 정리
  Future<void> cleanupExpired();
  
  /// 캐시 상태 정보
  Future<Map<String, dynamic>> getStats();
}

/// 바이너리 데이터 전용 캐시 저장소 인터페이스
abstract class BinaryCacheStorage {
  /// 바이너리 데이터 조회
  Future<Uint8List?> getBinary(String key);
  
  /// 바이너리 데이터 저장
  Future<void> setBinary(String key, Uint8List data, {Duration? ttl});
  
  /// 파일 경로로 저장 (로컬 전용)
  Future<String?> setFile(String key, Uint8List data, String extension, {Duration? ttl});
  
  /// 파일 경로 조회 (로컬 전용)
  Future<String?> getFilePath(String key);
}

/// 캐시 메타데이터
class CacheMetadata {
  final String key;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final DateTime? expiresAt;
  final int size;
  final String dataType;

  CacheMetadata({
    required this.key,
    required this.createdAt,
    required this.lastAccessedAt,
    this.expiresAt,
    required this.size,
    required this.dataType,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'createdAt': createdAt.toIso8601String(),
      'lastAccessedAt': lastAccessedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'size': size,
      'dataType': dataType,
    };
  }

  factory CacheMetadata.fromJson(Map<String, dynamic> json) {
    return CacheMetadata(
      key: json['key'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastAccessedAt: DateTime.parse(json['lastAccessedAt'] as String),
      expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt'] as String) : null,
      size: json['size'] as int,
      dataType: json['dataType'] as String,
    );
  }
} 