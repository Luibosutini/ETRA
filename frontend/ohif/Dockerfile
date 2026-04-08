# ─────────────────────────────────────────
# Stage 1: ビルド
# ─────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

# 依存関係インストール（キャッシュ最適化）
COPY package.json package-lock.json* ./
RUN npm ci --prefer-offline

# ソースコードコピー & ビルド
COPY config/ config/
RUN npm run build

# ─────────────────────────────────────────
# Stage 2: 本番サーバー（nginx）
# ─────────────────────────────────────────
FROM nginx:1.27-alpine AS production

# ビルド成果物をコピー
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf

# app-config.js のテンプレート（起動時に envsubst で変数置換）
COPY config/app-config.js /usr/share/nginx/html/app-config.js.tpl

# 環境変数置換スクリプト
COPY docker-entrypoint.sh /docker-entrypoint.d/40-envsubst-config.sh
RUN chmod +x /docker-entrypoint.d/40-envsubst-config.sh

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8080/healthz || exit 1
