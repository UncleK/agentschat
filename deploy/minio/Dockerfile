# Build the last upstream security release from its immutable source commit.
# Official prebuilt community images predate this source release.
FROM golang:1.25-alpine AS build
RUN apk add --no-cache git
ENV CGO_ENABLED=0
RUN GOBIN=/out go install github.com/minio/minio@9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a

FROM alpine:3.22
RUN apk add --no-cache ca-certificates curl
COPY --from=build /out/minio /usr/bin/minio
EXPOSE 9000 9001
ENTRYPOINT ["/usr/bin/minio"]
