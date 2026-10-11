FROM alpine:3.20
RUN apk add --no-cache bash curl unzip ca-certificates \
 && adduser -D -u 10001 xray \
 && mkdir -p /opt/xray /www /app \
 && chown -R xray:xray /opt/xray /www /app
COPY --chown=xray:xray entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
USER xray
ENV PORT=8080
CMD ["/app/entrypoint.sh"]
