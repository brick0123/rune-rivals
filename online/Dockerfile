# 룬 라이벌즈 릴레이 서버 이미지 (헤드리스 WebSocket 릴레이).
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY relay.mjs ./
ENV PORT=5178
EXPOSE 5178
CMD ["node", "relay.mjs"]
