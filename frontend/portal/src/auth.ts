import { UserManager, User } from 'oidc-client-ts'
import { getConfig } from './config'

let _manager: UserManager | null = null

function getManager(): UserManager {
  if (_manager) return _manager
  const cfg = getConfig()
  _manager = new UserManager({
    authority: cfg.cognitoAuthority,
    client_id: cfg.cognitoClientId,
    redirect_uri: cfg.cognitoRedirectUri,
    post_logout_redirect_uri: cfg.cognitoPostLogoutUri,
    response_type: 'code',
    scope: 'openid email profile',
    automaticSilentRenew: true,
    // Cognito: issuer と jwks は cognito-idp URL、OAuth エンドポイントは Hosted UI ドメイン
    metadata: {
      issuer: cfg.cognitoAuthority,
      authorization_endpoint: `${cfg.cognitoHostedUiDomain}/oauth2/authorize`,
      token_endpoint: `${cfg.cognitoHostedUiDomain}/oauth2/token`,
      userinfo_endpoint: `${cfg.cognitoHostedUiDomain}/oauth2/userInfo`,
      end_session_endpoint: `${cfg.cognitoHostedUiDomain}/logout`,
      jwks_uri: `${cfg.cognitoAuthority}/.well-known/jwks.json`,
    },
  })
  return _manager
}

export async function getUser(): Promise<User | null> {
  return getManager().getUser()
}

export async function getAccessToken(): Promise<string> {
  const user = await getUser()
  if (!user || user.expired) {
    throw new Error('Not authenticated')
  }
  return user.access_token
}

export async function isAdmin(): Promise<boolean> {
  const user = await getUser()
  if (!user) return false
  const groups: string[] = (user.profile['cognito:groups'] as string[] | undefined) ?? []
  return groups.includes('admin')
}

export async function signIn(): Promise<void> {
  await getManager().signinRedirect()
}

export async function signOut(): Promise<void> {
  const cfg = getConfig()
  // oidc-client-ts のストレージをクリア
  await getManager().removeUser()
  // Cognito 独自のログアウト URL へ直接遷移（標準 OIDC パラメータは不可）
  const logoutUrl =
    `${cfg.cognitoHostedUiDomain}/logout` +
    `?client_id=${encodeURIComponent(cfg.cognitoClientId)}` +
    `&logout_uri=${encodeURIComponent(cfg.cognitoPostLogoutUri)}`
  window.location.href = logoutUrl
}

export async function handleCallback(): Promise<User> {
  return getManager().signinRedirectCallback()
}

export function onSilentRenewError(cb: (err: Error) => void): void {
  getManager().events.addSilentRenewError(cb)
}
