import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { getSubscriptionStatus as getStatus } from './subscription/subscriptionStatus';
import { validateAppStoreReceipt as validateReceipt } from './subscription/receiptValidation';
import { notifyPurchaseComplete as notifyPurchase } from './subscription/purchaseNotification';

// Firebase Admin 초기화
admin.initializeApp();

/**
 * 사용자의 현재 구독 상태를 조회하는 함수
 */
export const getSubscriptionStatus = functions
  .region('asia-northeast3') // 서울 리전
  .https.onCall(async (data, context) => {
    try {
      // 인증 확인
      if (!context.auth) {
        throw new functions.https.HttpsError(
          'unauthenticated',
          '로그인이 필요합니다.'
        );
      }

      const uid = context.auth.uid;
      const forceRefresh = data.forceRefresh || false;

      functions.logger.info(`구독 상태 조회 시작: ${uid}`, { forceRefresh });

      const result = await getStatus(uid, forceRefresh);
      
      functions.logger.info(`구독 상태 조회 완료: ${uid}`, result);
      
      return result;
    } catch (error) {
      functions.logger.error('구독 상태 조회 실패:', error);
      throw new functions.https.HttpsError(
        'internal',
        '구독 상태 조회 중 오류가 발생했습니다.'
      );
    }
  });

/**
 * App Store Receipt을 검증하는 함수
 */
export const validateAppStoreReceipt = functions
  .region('asia-northeast3')
  .https.onCall(async (data, context) => {
    try {
      // 인증 확인
      if (!context.auth) {
        throw new functions.https.HttpsError(
          'unauthenticated',
          '로그인이 필요합니다.'
        );
      }

      const uid = context.auth.uid;
      const receiptData = data.receiptData;

      if (!receiptData) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          'Receipt 데이터가 필요합니다.'
        );
      }

      functions.logger.info(`Receipt 검증 시작: ${uid}`);

      const result = await validateReceipt(uid, receiptData);
      
      functions.logger.info(`Receipt 검증 완료: ${uid}`, { success: result.success });
      
      return result;
    } catch (error) {
      functions.logger.error('Receipt 검증 실패:', error);
      throw new functions.https.HttpsError(
        'internal',
        'Receipt 검증 중 오류가 발생했습니다.'
      );
    }
  });

/**
 * 구매 완료를 알리는 함수
 */
export const notifyPurchaseComplete = functions
  .region('asia-northeast3')
  .https.onCall(async (data, context) => {
    try {
      // 인증 확인
      if (!context.auth) {
        throw new functions.https.HttpsError(
          'unauthenticated',
          '로그인이 필요합니다.'
        );
      }

      const uid = context.auth.uid;
      const { productId, transactionId } = data;

      if (!productId || !transactionId) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          'productId와 transactionId가 필요합니다.'
        );
      }

      functions.logger.info(`구매 완료 알림 시작: ${uid}`, { productId, transactionId });

      const result = await notifyPurchase(uid, productId, transactionId);
      
      functions.logger.info(`구매 완료 알림 처리 완료: ${uid}`, { success: result.success });
      
      return result;
    } catch (error) {
      functions.logger.error('구매 완료 알림 실패:', error);
      throw new functions.https.HttpsError(
        'internal',
        '구매 완료 알림 처리 중 오류가 발생했습니다.'
      );
    }
  });

/**
 * 헬스체크 함수 (서버 상태 확인용)
 */
export const healthCheck = functions
  .region('asia-northeast3')
  .https.onRequest((req, res) => {
    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      version: '1.0.0'
    });
  }); 