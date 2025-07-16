import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/payment/in_app_purchase_service.dart';
import '../../core/services/subscription/unified_subscription_manager.dart';
import '../../core/services/notification/notification_service.dart';
import '../../core/theme/tokens/color_tokens.dart';

class PaymentDebugScreen extends StatefulWidget {
  const PaymentDebugScreen({Key? key}) : super(key: key);

  @override
  State<PaymentDebugScreen> createState() => _PaymentDebugScreenState();
}

class _PaymentDebugScreenState extends State<PaymentDebugScreen> {
  final List<String> _logs = [];
  bool _isLoading = false;
  String? _currentUserId;
  Map<String, dynamic>? _userDoc;
  Map<String, dynamic>? _subscriptionState;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _addLog('🚀 Payment Debug Screen 초기화됨');
    _addLog('👤 현재 사용자: ${_currentUserId ?? "없음"}');
  }

  void _addLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
    setState(() {
      _logs.add('${DateTime.now().toIso8601String().substring(11, 19)} $message');
    });
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  /// 🔹 1단계: 현재 사용자 Firestore 정보 확인
  Future<void> _checkUserDocument() async {
    if (_currentUserId == null) {
      _addLog('❌ 로그인된 사용자 없음');
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      _addLog('🔍 1단계: 사용자 문서 확인 중...');
      
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();
      
      if (userDoc.exists) {
        _userDoc = userDoc.data();
        _addLog('✅ 사용자 문서 존재');
        _addLog('📄 구독 정보: ${_userDoc?['subscription'] ?? "없음"}');
        _addLog('📄 hasSeenWelcomeModal: ${_userDoc?['hasSeenWelcomeModal'] ?? false}');
        _addLog('📄 hasUsedTrial: ${_userDoc?['hasUsedTrial'] ?? false}');
        _addLog('📄 originalTransactionId: ${_userDoc?['originalTransactionId'] ?? "없음"}');
      } else {
        _addLog('❌ 사용자 문서 없음');
      }
    } catch (e) {
      _addLog('❌ 사용자 문서 확인 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 🔹 2단계: StoreKit 구매 가능 여부 확인
  Future<void> _checkStoreKitAvailability() async {
    setState(() => _isLoading = true);
    
    try {
      _addLog('🔍 2단계: StoreKit 가용성 확인 중...');
      
      final purchaseService = InAppPurchaseService();
      await purchaseService.initialize();
      
      _addLog('✅ StoreKit 초기화 완료');
      
      // 상품 정보 확인
      final products = await purchaseService.availableProducts;
      _addLog('📦 사용 가능한 상품: ${products.length}개');
      
      for (final product in products) {
        _addLog('   - ${product.id}: ${product.title} (${product.price})');
      }
      
    } catch (e) {
      _addLog('❌ StoreKit 확인 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 🔹 3단계: 구독 상태 확인 (캐시 없이)
  Future<void> _checkSubscriptionState() async {
    setState(() => _isLoading = true);
    
    try {
      _addLog('🔍 3단계: 구독 상태 확인 중...');
      
      final unifiedManager = UnifiedSubscriptionManager();
      
      // 캐시 무효화 후 새로 가져오기
      unifiedManager.invalidateCache();
      final entitlements = await unifiedManager.getSubscriptionEntitlements(forceRefresh: true);
      
      _subscriptionState = {
        'entitlement': entitlements['entitlement'],
        'subscriptionStatus': entitlements['subscriptionStatus'],
        'isPremium': entitlements['isPremium'],
        'isTrial': entitlements['isTrial'],
        'isExpired': entitlements['isExpired'],
        'hasUsedTrial': entitlements['hasUsedTrial'],
        'statusMessage': entitlements['statusMessage'],
      };
      
      _addLog('✅ 구독 상태 확인 완료');
      _addLog('📊 권한: ${entitlements['entitlement']}');
      _addLog('📊 구독 상태: ${entitlements['subscriptionStatus']}');
      _addLog('📊 프리미엄: ${entitlements['isPremium']}');
      _addLog('📊 체험: ${entitlements['isTrial']}');
      _addLog('📊 만료: ${entitlements['isExpired']}');
      _addLog('📊 체험 사용 이력: ${entitlements['hasUsedTrial']}');
      _addLog('📊 상태 메시지: ${entitlements['statusMessage']}');
      
    } catch (e) {
      _addLog('❌ 구독 상태 확인 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 🔹 4단계: EntitlementEngine 직접 확인
  Future<void> _checkEntitlementEngine() async {
    setState(() => _isLoading = true);
    
    try {
      _addLog('🔍 4단계: UnifiedSubscriptionManager 확인 중...');
      
      final subscriptionManager = UnifiedSubscriptionManager();
      final entitlements = await subscriptionManager.getSubscriptionEntitlements(forceRefresh: true);
      
      _addLog('✅ UnifiedSubscriptionManager 확인 완료');
      _addLog('🎫 구독 권한: ${entitlements['entitlement']}');
      _addLog('🎫 구독 상태: ${entitlements['subscriptionStatus']}');
      
    } catch (e) {
      _addLog('❌ EntitlementEngine 확인 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 🔹 5단계: 테스트 구매 시도
  Future<void> _attemptTestPurchase() async {
    setState(() => _isLoading = true);
    
    try {
      _addLog('🔍 5단계: 테스트 구매 시도 중...');
      
      final purchaseService = InAppPurchaseService();
      
      // 구매 결과 콜백 설정
      purchaseService.setOnPurchaseResult((success, transactionId, error) {
        if (success) {
          _addLog('✅ 구매 성공! Transaction ID: $transactionId');
          
          // 구매 성공 후 30초 후 상태 재확인
          Future.delayed(const Duration(seconds: 30), () {
            _addLog('🔄 30초 후 구독 상태 재확인...');
            _checkSubscriptionState();
          });
          
        } else {
          _addLog('❌ 구매 실패: $error');
        }
      });
      
      // 월간 구매 시도 (Trial offer 포함)
      purchaseService.setTrialContext(true); // Debug 화면에서는 Trial로 가정
      final success = await purchaseService.buyProduct(InAppPurchaseService.premiumMonthlyId);
      
      if (success) {
        _addLog('🛒 구매 요청 성공 - 결과 대기 중...');
      } else {
        _addLog('❌ 구매 요청 실패');
      }
      
    } catch (e) {
      _addLog('❌ 구매 시도 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 🔹 6단계: 서버 강제 동기화
  Future<void> _forceSyncWithServer() async {
    setState(() => _isLoading = true);
    
    try {
      _addLog('🔍 6단계: 서버 동기화 시도 중...');
      
      final subscriptionManager = UnifiedSubscriptionManager();
      // initialize 메서드는 더 이상 존재하지 않으므로 제거
      
      _addLog('✅ UnifiedSubscriptionManager 초기화됨');
      
      // 10초 대기 후 상태 확인
      await Future.delayed(const Duration(seconds: 10));
      
      _addLog('🔄 서버 동기화 후 상태 재확인...');
      await _checkSubscriptionState();
      
    } catch (e) {
      _addLog('❌ 서버 동기화 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 🔹 알림 시스템 상태 확인
  Future<void> _checkNotificationStatus() async {
    setState(() => _isLoading = true);
    
    try {
      _addLog('🔔 알림 시스템 상태 확인 중...');
      
      final purchaseService = InAppPurchaseService();
      await purchaseService.checkNotificationSystemStatus();
      
      _addLog('✅ 알림 시스템 상태 확인 완료 (로그 참조)');
      
    } catch (e) {
      _addLog('❌ 알림 시스템 상태 확인 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 🔹 알림 스케줄링 테스트
  Future<void> _testNotificationScheduling() async {
    setState(() => _isLoading = true);
    
    try {
      _addLog('📅 알림 스케줄링 테스트 중...');
      
      final purchaseService = InAppPurchaseService();
      await purchaseService.initialize();
      
      // 현재 구독 상태 확인
      final subscriptionManager = UnifiedSubscriptionManager();
      final entitlements = await subscriptionManager.getSubscriptionEntitlements(forceRefresh: true);
      
      _addLog('📊 현재 구독 상태: ${entitlements['entitlement']}');
      
      // 트라이얼 만료일 확인
      final expirationDateStr = entitlements['expirationDate'] as String?;
      if (expirationDateStr != null) {
        final expirationDate = DateTime.parse(expirationDateStr);
        _addLog('📅 만료일: ${expirationDate.toString()}');
        
        // 알림 스케줄링 테스트
        await purchaseService.scheduleNotificationsIfNeeded(InAppPurchaseService.premiumMonthlyId);
        _addLog('✅ 알림 스케줄링 테스트 완료');
      } else {
        _addLog('⚠️ 만료일 정보 없음 - 트라이얼 상태가 아닙니다');
        _addLog('💡 7일 무료체험 구매 후 다시 테스트해보세요');
        
        // 즉시 테스트 알림 표시
        _addLog('🧪 즉시 테스트 알림 표시 시도...');
        // NotificationService를 직접 사용
        final notificationService = NotificationService();
        await notificationService.showTestNotification();
        _addLog('✅ 즉시 테스트 알림 표시 완료');
      }
      
    } catch (e) {
      _addLog('❌ 알림 스케줄링 테스트 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 🔹 전체 플로우 테스트
  Future<void> _runFullTest() async {
    _clearLogs();
    _addLog('🚀 전체 플로우 테스트 시작');
    
    await _checkUserDocument();
    await Future.delayed(const Duration(seconds: 1));
    
    await _checkStoreKitAvailability();
    await Future.delayed(const Duration(seconds: 1));
    
    await _checkSubscriptionState();
    await Future.delayed(const Duration(seconds: 1));
    
    await _checkEntitlementEngine();
    await Future.delayed(const Duration(seconds: 1));
    
    _addLog('✅ 전체 플로우 테스트 완료');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Debug'),
        backgroundColor: ColorTokens.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _runFullTest,
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: _clearLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // 버튼 그리드
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _checkUserDocument,
                        child: const Text('1. 사용자 문서'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _checkStoreKitAvailability,
                        child: const Text('2. StoreKit'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _checkSubscriptionState,
                        child: const Text('3. 구독 상태'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _checkEntitlementEngine,
                        child: const Text('4. Entitlement'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _attemptTestPurchase,
                        child: const Text('5. 테스트 구매'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _forceSyncWithServer,
                        child: const Text('6. 서버 동기화'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _checkNotificationStatus,
                        child: const Text('🔔 알림 확인'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _testNotificationScheduling,
                        child: const Text('📅 알림 테스트'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _runFullTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ColorTokens.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('전체 플로우 테스트'),
                  ),
                ),
              ],
            ),
          ),
          
          // 로딩 인디케이터
          if (_isLoading)
            const LinearProgressIndicator(),
          
          // 로그 영역
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  Color textColor = Colors.black;
                  
                  if (log.contains('❌')) {
                    textColor = Colors.red;
                  } else if (log.contains('✅')) {
                    textColor = Colors.green;
                  } else if (log.contains('🔍')) {
                    textColor = Colors.blue;
                  } else if (log.contains('⚠️')) {
                    textColor = Colors.orange;
                  }
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      log,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: textColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
} 