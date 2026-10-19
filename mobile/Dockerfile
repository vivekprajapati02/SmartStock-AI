# SmartStock AI web client: Flutter web build served by nginx.
# nginx also reverse-proxies /api and /health to the backend, so the browser
# talks to a single origin (no CORS, one preview port).

ARG FLUTTER_VERSION=3.47.4

FROM ghcr.io/cirruslabs/flutter:${FLUTTER_VERSION} AS build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
# Empty API_BASE_URL => same-origin requests to /api/v1 (proxied by nginx).
RUN flutter build web --release --dart-define=API_BASE_URL=

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY --from=build /app/build/web /usr/share/nginx/html
ENV API_UPSTREAM=http://api:8000
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
