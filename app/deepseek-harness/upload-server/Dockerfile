# Minimal, dependency-free upload endpoint — see server.js's header comment
# for why this exists (dsh has no upload/attachment RPC of its own).
FROM node:22-slim
WORKDIR /app
COPY server.js .
EXPOSE 8081
CMD ["node", "server.js"]
