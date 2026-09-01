# syntax=docker/dockerfile:1.7

FROM node:22-bookworm AS frontend
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates build-essential golang-go && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git clone --depth 1 https://github.com/sipeed/picoclaw.git picoclaw
WORKDIR /src/picoclaw
RUN cd web/frontend && pnpm install --frozen-lockfile && pnpm build:backend

FROM golang:1.25-bookworm AS picoclaw-builder
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates build-essential nodejs npm && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git clone --depth 1 https://github.com/sipeed/picoclaw.git picoclaw
COPY --from=frontend /src/picoclaw/web/backend/dist /src/picoclaw/web/backend/dist
WORKDIR /src/picoclaw
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/picoclaw ./cmd/picoclaw
RUN CGO_ENABLED=0 go build -trimpath -tags 'goolm,stdjson' -ldflags='-s -w' -o /out/picoclaw-launcher ./web/backend

FROM debian:bookworm AS picolm-builder
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates build-essential && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git clone --depth 1 https://github.com/RightNow-AI/picolm.git picolm
WORKDIR /src/picolm
RUN make native

FROM debian:bookworm AS model
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /models && curl -fL --retry 5 --retry-all-errors -o /models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf \
  'https://huggingface.co/nitsuai/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf'

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libstdc++6 procps && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=picoclaw-builder /out/picoclaw /app/picoclaw
COPY --from=picoclaw-builder /out/picoclaw-launcher /app/picoclaw-launcher
COPY --from=picolm-builder /src/picolm/picolm /app/picolm
COPY --from=model /models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf /app/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf
COPY config/config.json /config/config.json
COPY local-llm-proxy.go /app/local-llm-proxy.go
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/picoclaw /app/picolm /app/picoclaw-launcher /app/entrypoint.sh && mkdir -p /app/workspace /app/proxy
ENV PICOCLAW_CONFIG=/config/config.json \
    PICOCLAW_HOME=/app \
    PICOCLAW_BINARY=/app/picoclaw
EXPOSE 8080
ENTRYPOINT ["/app/entrypoint.sh"]
