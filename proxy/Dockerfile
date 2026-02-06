FROM ghcr.io/xtls/xray-core:26.2.6 AS xray-bin
FROM alpine:3.21

ENV SNI=www.samsung.com
ENV SHORT_ID=""
ENV ENABLE_PQ=true
ENV ENABLE_STATS=false

RUN set -e && \
    apk add --no-cache bash jq curl netcat-openbsd libqrencode && \
    addgroup -g 1000 app && \
    adduser -S -G app -u 1000 -H -h /opt/xray xray && \
    mkdir -p /opt/xray/config && \
    chown -R xray:app /opt/xray

COPY --from=xray-bin /usr/local/bin/xray /usr/local/bin/xray
COPY --from=xray-bin /usr/local/share/xray/ /usr/local/share/xray/

WORKDIR /opt/xray

COPY --chown=xray:app proxy/config.template.json config/config.template.json
COPY --chown=xray:app proxy/entrypoint.sh .
COPY --chown=xray:app proxy/client-config.sh .
RUN chmod +x entrypoint.sh client-config.sh

USER xray

EXPOSE 443

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD nc -z 127.0.0.1 443 || exit 1

ENTRYPOINT ["bash", "./entrypoint.sh"]
