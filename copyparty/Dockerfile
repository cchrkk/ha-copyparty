FROM python:3.13-alpine

ENV LANG=C.UTF-8 \
    PYTHONUNBUFFERED=1

# jq + curl: read the app options and ask Supervisor for the ingress path
# nginx: re-adds the ingress prefix Home Assistant strips before forwarding
# ffmpeg: video thumbnails, audio metadata and on-the-fly transcoding
RUN apk add --no-cache \
        curl \
        ffmpeg \
        jq \
        nginx \
        tzdata

ARG COPYPARTY_VERSION=1.20.26
RUN pip install --no-cache-dir "copyparty==${COPYPARTY_VERSION}"

COPY run.sh /run.sh
RUN chmod 0755 /run.sh

LABEL \
    org.opencontainers.image.title="copyparty" \
    org.opencontainers.image.description="File server with web UI, resumable uploads and WebDAV for the Home Assistant folders" \
    org.opencontainers.image.source="https://github.com/cchrkk/ha-copyparty" \
    org.opencontainers.image.licenses="MIT"

CMD ["/run.sh"]
