/**
 * OHIF Viewer アプリケーション設定
 *
 * 実行時に以下の環境変数を参照する（nginx envsubst または Dockerfile 経由で注入）:
 *   DATASTORE_ID       : AWS HealthImaging データストア ID
 *   REGION             : AWS リージョン（例: us-east-1）
 *   COGNITO_USER_POOL_ID : Cognito ユーザープール ID
 *   COGNITO_CLIENT_ID  : Cognito アプリクライアント ID
 *   APP_URL            : アプリのベース URL（例: https://viewer.example.com）
 */

window.config = {
  routerBasename: '/ohif',
  showStudyList: true,
  showWarningMessageForCrossOrigin: true,
  showCPUFallbackMessage: true,
  showLoadingIndicator: true,
  strictZSpacingForVolumeViewport: true,
  maxNumberOfWebWorkers: 3,

  // ─────────────────────────────────────────
  // デフォルトデータソース
  // ─────────────────────────────────────────
  defaultDataSourceName: 'aws-healthimaging',

  dataSources: [
    {
      namespace: '@ohif/extension-default.dataSourcesModule.awsHealthImaging',
      sourceName: 'aws-healthimaging',
      configuration: {
        friendlyName: 'AWS HealthImaging',
        datastoreId: '887c4218fefa4743a239eed78d87278a',
        region: 'us-east-1',
        // Cognito から取得した ID トークンを Authorization ヘッダーで渡す
        // OHIF の aws-healthimaging datasource は自動で Cognito トークンを付与する
      },
    },
  ],

  // ─────────────────────────────────────────
  // Cognito OIDC 認証
  // ─────────────────────────────────────────
  oidc: [
    {
      authority: 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_ctYLjFt8H',
      client_id: '7288tp5gelq4b2slgae3on2ju4',
      redirect_uri: 'https://d1jsy5521583dy.cloudfront.net/ohif/callback',
      post_logout_redirect_uri: 'https://d1jsy5521583dy.cloudfront.net/ohif/logout',
      response_type: 'code',
      scope: 'openid email profile',
      // Authorization Code Flow with PKCE
      automaticSilentRenew: true,
      filterProtocolClaims: true,
      loadUserInfo: true,
    },
  ],

  // ─────────────────────────────────────────
  // 使用する拡張・モード
  // ─────────────────────────────────────────
  extensions: [],
  modes: [],

  // ─────────────────────────────────────────
  // UI カスタマイズ
  // ─────────────────────────────────────────
  customizationService: {
    'studyBrowser.studyMenuItem': [],
  },
};
