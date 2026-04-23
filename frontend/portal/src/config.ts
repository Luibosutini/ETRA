interface EtraConfig {
  apiEndpoint: string
  cognitoAuthority: string
  cognitoHostedUiDomain: string
  cognitoClientId: string
  cognitoRedirectUri: string
  cognitoPostLogoutUri: string
  region: string
}

declare global {
  interface Window {
    __ETRA_CONFIG__: EtraConfig
  }
}

export function getConfig(): EtraConfig {
  const cfg = window.__ETRA_CONFIG__
  if (!cfg) throw new Error('window.__ETRA_CONFIG__ が設定されていません。config.js を確認してください。')
  return cfg
}
