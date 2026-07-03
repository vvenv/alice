# linux/amd64 release 本地构建镜像（apt + pnpm 预装，层缓存跨次构建复用）
# 构建时在容器内 /build 隔离安装依赖，/src 只读挂载，不修改宿主机 node_modules
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-bookworm-slim

ARG PNPM_VERSION=11.9.0
ENV DEBIAN_FRONTEND=noninteractive
ENV CI=true

RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable \
  && corepack prepare "pnpm@${PNPM_VERSION}" --activate

WORKDIR /work
