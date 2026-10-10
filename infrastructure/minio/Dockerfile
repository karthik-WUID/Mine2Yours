# Local S3-compatibility helper. Upstream is archived and AGPL-3.0 licensed.
# Build the official pinned source because historical public binary images are unavailable.
FROM golang:1.24.8-bookworm AS build
WORKDIR /source
ADD https://github.com/minio/minio/archive/9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a.tar.gz /tmp/minio-source.tar.gz
RUN tar -xzf /tmp/minio-source.tar.gz --strip-components=1 -C /source && rm /tmp/minio-source.tar.gz
RUN go build -trimpath -ldflags="-s -w" -o /minio .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 minio && useradd --uid 10001 --gid minio --no-create-home minio \
    && mkdir /data && chown minio:minio /data
COPY --from=build /minio /usr/local/bin/minio
COPY --from=build /source/LICENSE /usr/share/doc/minio/LICENSE
USER minio
EXPOSE 9000 9001
ENTRYPOINT ["/usr/local/bin/minio"]
