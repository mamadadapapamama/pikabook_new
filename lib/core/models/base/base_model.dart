/// 🏗️ 기본 모델 클래스들
/// 공통 패턴을 추상화하여 코드 중복을 줄입니다.

import 'package:equatable/equatable.dart';
import '../../utils/enum_utils.dart';

/// 🎯 기본 모델 인터페이스
abstract class BaseModel {
  /// JSON 직렬화
  Map<String, dynamic> toJson();
  
  /// 복사본 생성 (선택적 구현)
  BaseModel copyWith();
}

/// 🔧 JSON 변환 가능한 모델 기본 클래스
abstract class JsonModel extends Equatable implements BaseModel {
  const JsonModel();
  
  /// JSON에서 모델 생성 (하위 클래스에서 구현)
  static JsonModel fromJson(Map<String, dynamic> json) {
    throw UnimplementedError('fromJson must be implemented in subclasses');
  }
}

/// 📋 팩토리 메서드를 가진 모델 기본 클래스
abstract class FactoryModel extends JsonModel {
  const FactoryModel();
  
  /// ID 기반 팩토리 메서드 (하위 클래스에서 구현)
  static FactoryModel fromId(String id) {
    throw UnimplementedError('fromId must be implemented in subclasses');
  }
}

/// 🔄 상태를 가진 모델 기본 클래스
abstract class StatefulModel<T extends Enum> extends JsonModel {
  final T status;
  final DateTime? timestamp;
  
  const StatefulModel({
    required this.status,
    this.timestamp,
  });
  
  /// 상태 문자열 변환
  String get statusString => EnumUtils.enumToString(status);
  
  /// 상태가 활성인지 확인 (하위 클래스에서 구현)
  bool get isActive;
  
  /// 상태가 만료되었는지 확인 (하위 클래스에서 구현)
  bool get isExpired;
}

/// 🎭 표시 이름을 가진 모델 기본 클래스
abstract class DisplayableModel extends JsonModel {
  final String id;
  final String name;
  
  const DisplayableModel({
    required this.id,
    required this.name,
  });
  
  /// 표시용 이름 (하위 클래스에서 커스터마이즈 가능)
  String get displayName => name;
  
  @override
  List<Object?> get props => [id, name];
}

/// 🕐 타임스탬프를 가진 모델 기본 클래스
abstract class TimestampedModel extends JsonModel {
  final DateTime? createdAt;
  final DateTime? updatedAt;
  
  const TimestampedModel({
    this.createdAt,
    this.updatedAt,
  });
  
  /// 생성 시간 문자열
  String? get createdAtString => createdAt?.toIso8601String();
  
  /// 업데이트 시간 문자열
  String? get updatedAtString => updatedAt?.toIso8601String();
  
  @override
  List<Object?> get props => [createdAt, updatedAt];
}

/// 🔗 ID와 이름을 가진 기본 엔티티 클래스
abstract class BaseEntity extends DisplayableModel {
  const BaseEntity({
    required super.id,
    required super.name,
  });
  
  @override
  String toString() => '${runtimeType}(id: $id, name: $name)';
}

/// 📊 상태와 타임스탬프를 모두 가진 모델
abstract class StatefulTimestampedModel<T extends Enum> extends StatefulModel<T> {
  final DateTime? createdAt;
  final DateTime? updatedAt;
  
  const StatefulTimestampedModel({
    required super.status,
    super.timestamp,
    this.createdAt,
    this.updatedAt,
  });
  
  @override
  List<Object?> get props => [status, timestamp, createdAt, updatedAt];
}