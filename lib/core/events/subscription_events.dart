import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/subscription_state.dart';
import '../services/subscription/unified_subscription_manager.dart';

/// 구독 이벤트 타입
enum SubscriptionEventType {
  purchased,        // 구매 완료
  trialStarted,     // 체험 시작
  expired,          // 만료
  cancelled,        // 취소
  refunded,         // 환불
  renewed,          // 갱신
  gracePeriod,      // 유예 기간
  webhookReceived,  // 웹훅 수신
  stateRefreshed,   // 상태 새로고침
}

/// 구독 이벤트 데이터
class SubscriptionEvent {
  final SubscriptionEventType type;
  final SubscriptionState state;
  final String context;  // 'purchase', 'webhook', 'timer' 등
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;

  SubscriptionEvent({
    required this.type,
    required this.state,
    required this.context,
    this.metadata,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'SubscriptionEvent(type: $type, context: $context, entitlement: ${state.entitlement.value}, status: ${state.subscriptionStatus.value})';
  }
}

/// 구독 이벤트 관리자 (싱글톤)
/// 
/// 🎯 핵심 책임:
/// - 구독 이벤트 중앙 관리 및 브로드캐스트
/// - 이벤트 발행 편의 메서드 제공  
/// - 이벤트 리스너 관리
/// 
/// 🔄 이벤트 흐름:
/// 1. UnifiedSubscriptionManager가 구독 상태 변경 감지
/// 2. SubscriptionEventManager.emitXXX() 호출
/// 3. 모든 리스너들(BannerManager 등)에게 브로드캐스트
class SubscriptionEventManager {
  static final SubscriptionEventManager _instance = SubscriptionEventManager._internal();
  factory SubscriptionEventManager() => _instance;
  SubscriptionEventManager._internal();

  final StreamController<SubscriptionEvent> _eventController = StreamController<SubscriptionEvent>.broadcast();
  
  /// 이벤트 스트림 (구독용)
  Stream<SubscriptionEvent> get eventStream => _eventController.stream;

  /// 🎯 기본 이벤트 발행
  void emit(SubscriptionEvent event) {
    if (kDebugMode) {
      debugPrint('📡 [SubscriptionEventManager] 이벤트 발행: ${event.type} (${event.context})');
      debugPrint('   상태: ${event.state.entitlement.value} / ${event.state.subscriptionStatus.value}');
    }
    
    _eventController.add(event);
  }

  /// 🎯 구독 상태와 함께 이벤트 발행 (UnifiedSubscriptionManager에서 호출)
  void emitWithState({
    required SubscriptionEventType eventType,
    required SubscriptionState state,
    String context = 'unknown',
    Map<String, dynamic>? metadata,
  }) {
    final event = SubscriptionEvent(
      type: eventType,
      state: state,
      context: context,
      metadata: metadata,
    );
    
    emit(event);
  }

  /// 🎯 편의 메서드들 - 구독 상태와 함께 이벤트 발행
  void emitPurchaseCompleted(SubscriptionState state, {String context = 'purchase', Map<String, dynamic>? metadata}) {
    emitWithState(
      eventType: SubscriptionEventType.purchased,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  void emitTrialStarted(SubscriptionState state, {String context = 'trial', Map<String, dynamic>? metadata}) {
    emitWithState(
      eventType: SubscriptionEventType.trialStarted,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  void emitExpired(SubscriptionState state, {String context = 'webhook', Map<String, dynamic>? metadata}) {
    emitWithState(
      eventType: SubscriptionEventType.expired,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  void emitCancelled(SubscriptionState state, {String context = 'webhook', Map<String, dynamic>? metadata}) {
    emitWithState(
      eventType: SubscriptionEventType.cancelled,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  void emitRefunded(SubscriptionState state, {String context = 'webhook', Map<String, dynamic>? metadata}) {
    emitWithState(
      eventType: SubscriptionEventType.refunded,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  void emitWebhookReceived(SubscriptionState state, {String context = 'webhook', Map<String, dynamic>? metadata}) {
    emitWithState(
      eventType: SubscriptionEventType.webhookReceived,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  void emitStateRefreshed(SubscriptionState state, {String context = 'refresh', Map<String, dynamic>? metadata}) {
    emitWithState(
      eventType: SubscriptionEventType.stateRefreshed,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  /// 정리
  void dispose() {
    _eventController.close();
  }
}

/// 구독 이벤트 리스너 추상 클래스
abstract class SubscriptionEventListener {
  late StreamSubscription<SubscriptionEvent> _subscription;
  
  /// 이벤트 구독 시작 (단순화됨)
  void startListening() {
    // UnifiedSubscriptionManager에서 이벤트 스트림이 제거되었으므로 단순화
    if (kDebugMode) {
      debugPrint('⚠️ [${runtimeType}] 구독 이벤트 스트림 기능 제거됨 - 단순화된 구조');
    }
  }
  
  /// 이벤트 구독 중지
  void stopListening() {
    _subscription.cancel();
    if (kDebugMode) {
      debugPrint('🔇 [${runtimeType}] 구독 이벤트 리스닝 중지');
    }
  }
  
  /// 구독 이벤트 처리 (하위 클래스에서 구현)
  void onSubscriptionEvent(SubscriptionEvent event);
} 