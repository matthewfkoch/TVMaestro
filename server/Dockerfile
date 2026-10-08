FROM node:22-alpine AS web
WORKDIR /web
COPY web/package.json web/package-lock.json* ./
RUN npm ci
COPY web/ ./
RUN npm run build

FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TVMAESTRO_PORT=6790 \
    TVMAESTRO_DATA_DIR=/data

WORKDIR /app

# adb is required for CEC power on Shield/ATV: sideloaded apps cannot
# inject SLEEP/WAKEUP with enough privilege for HdmiControlService.
# gcc/g++ compile pyatv's miniaudio on linux/arm64 (no published wheel) and
# are purged in the same layer so they are not part of the runtime image.
COPY server/requirements.txt .
RUN apt-get update \
    && apt-get install -y --no-install-recommends adb gcc g++ \
    && pip install --no-cache-dir -r requirements.txt \
    && apt-get purge -y gcc g++ \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY server/tvmaestro ./tvmaestro
COPY config.example.json /app/config.example.json
# Drop any stale hashed bundles that arrived with the Python package, then
# install the web image built above.
RUN rm -rf ./tvmaestro/web
COPY --from=web /web/dist ./tvmaestro/web

VOLUME ["/data"]
EXPOSE 6790

CMD ["sh", "-c", "uvicorn tvmaestro.main:app --host 0.0.0.0 --port ${TVMAESTRO_PORT}"]
