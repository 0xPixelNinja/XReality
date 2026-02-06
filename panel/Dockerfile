FROM node:22-alpine

WORKDIR /app

COPY panel/package.json ./
RUN npm install --production && npm cache clean --force

COPY panel/server.js .
COPY panel/public/ ./public/

RUN addgroup -g 1000 -S app 2>/dev/null || true && \
    chown -R node:node /app

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://127.0.0.1:3000/api/status > /dev/null 2>&1 || exit 1

CMD ["node", "server.js"]
