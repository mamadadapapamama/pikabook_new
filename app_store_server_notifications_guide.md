# App Store Server Notifications 설정 가이드

## 🎯 목표
유저가 App Store에서 구독을 취소하면 **즉시** 배너가 표시되도록 하기

## 📡 App Store Server Notifications란?
Apple이 구독 상태 변경(취소, 갱신, 만료 등) 시 서버로 실시간 알림을 보내는 시스템

## 🛠️ 구현 단계

### **1단계: Firebase Functions 엔드포인트 생성**

```typescript
// firebase/functions/src/index.ts
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

// App Store Server Notifications 웹훅 엔드포인트
export const appStoreNotifications = functions.https.onRequest(async (req, res) => {
  try {
    console.log('📡 App Store Server Notification 수신:', req.body);
    
    // Apple의 JWS(JSON Web Signature) 검증
    const notificationPayload = verifyAndDecodeNotification(req.body);
    
    if (!notificationPayload) {
      res.status(400).send('Invalid notification');
      return;
    }
    
    // 알림 타입별 처리
    const { notificationType, subtype, data } = notificationPayload;
    
    switch (notificationType) {
      case 'DID_CANCEL_SUBSCRIPTION':
        await handleSubscriptionCancellation(data);
        break;
      case 'DID_EXPIRE_SUBSCRIPTION':
        await handleSubscriptionExpiration(data);
        break;
      case 'DID_RENEW_SUBSCRIPTION':
        await handleSubscriptionRenewal(data);
        break;
      // 기타 알림 타입들...
    }
    
    res.status(200).send('OK');
  } catch (error) {
    console.error('❌ App Store Notification 처리 실패:', error);
    res.status(500).send('Error processing notification');
  }
});

// 구독 취소 처리
async function handleSubscriptionCancellation(transactionInfo: any) {
  const { originalTransactionId, expiresDate } = transactionInfo;
  
  // Firestore에서 사용자 찾기
  const userSnapshot = await admin.firestore()
    .collection('users')
    .where('originalTransactionId', '==', originalTransactionId)
    .get();
    
  if (!userSnapshot.empty) {
    const userDoc = userSnapshot.docs[0];
    
    // 구독 정보 업데이트 (취소 상태로)
    await userDoc.ref.update({
      'subscription.autoRenewStatus': false,
      'subscription.isCancelled': true,
      'subscription.cancelledAt': admin.firestore.FieldValue.serverTimestamp(),
      // 체험/구독 기간은 expiresDate까지 유지
    });
    
    console.log('✅ 구독 취소 처리 완료:', userDoc.id);
  }
}
```

### **2단계: App Store Connect에서 웹훅 URL 설정**

1. **App Store Connect** → **My Apps** → **앱 선택**
2. **App Information** → **App Store Server Notifications**
3. **Server Notification URL** 입력:
   ```
   https://your-project.cloudfunctions.net/appStoreNotifications
   ```
4. **Sandbox/Production** 환경별 URL 설정

### **3단계: JWS 서명 검증 구현**

```typescript
import * as jwt from 'jsonwebtoken';

function verifyAndDecodeNotification(signedPayload: string) {
  try {
    // Apple의 공개 키로 JWS 검증
    const decoded = jwt.verify(signedPayload, getApplePublicKey(), {
      algorithms: ['ES256']
    });
    
    return decoded;
  } catch (error) {
    console.error('❌ JWS 검증 실패:', error);
    return null;
  }
}

function getApplePublicKey() {
  // Apple의 공개 키 (App Store Connect에서 다운로드)
  return `-----BEGIN PUBLIC KEY-----
  MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
  -----END PUBLIC KEY-----`;
}
```

### **4단계: 클라이언트 앱에서 실시간 감지**

현재 구현은 이미 준비되어 있음:
- ✅ Firebase Functions에서 `autoRenewStatus` 받아옴
- ✅ 5분 캐시로 성능 최적화
- ✅ 포그라운드 복귀 시 자동 새로고침

## ⚡ 즉시 배너 표시를 위한 추가 최적화

### **Firebase Cloud Messaging 활용**
```typescript
// 구독 취소 시 FCM 푸시 전송
async function handleSubscriptionCancellation(transactionInfo: any) {
  // ... 기존 로직 ...
  
  // FCM으로 앱에 즉시 알림
  const message = {
    token: userFCMToken,
    data: {
      type: 'subscription_cancelled',
      autoRenewStatus: 'false'
    }
  };
  
  await admin.messaging().send(message);
}
```

### **클라이언트에서 FCM 처리**
```dart
// lib/core/services/notification/fcm_service.dart
FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  if (message.data['type'] == 'subscription_cancelled') {
    // 즉시 구독 상태 새로고침
    _loadSubscriptionStatus(forceRefresh: true);
  }
});
```

## 📋 체크리스트

- [ ] Firebase Functions 프로젝트 설정
- [ ] App Store Server Notifications 엔드포인트 구현
- [ ] JWS 서명 검증 로직 추가
- [ ] App Store Connect에서 웹훅 URL 설정
- [ ] Sandbox 환경에서 테스트
- [ ] Production 환경 배포
- [ ] FCM 즉시 알림 (선택사항)

## 🔄 현재 상황

**좋은 소식**: 클라이언트 앱은 이미 준비 완료! ✅
**필요한 작업**: Firebase Functions 백엔드 개발 📝

구독 취소 후 **5분 이내** 배너 표시를 위해서는 위의 백엔드 개발이 필요합니다. 