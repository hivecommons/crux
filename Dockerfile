# ghcr.io/hivecommons/crux — the crux binary plus tmux, which the runtime
# drives to host agent processes. Built by goreleaser (.goreleaser.yaml) from
# the already cross-compiled binary for each platform; `docker build` from a
# checkout works too via the builder stage.
ARG GO_IMAGE=golang:1.26-alpine

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS build
ARG TARGETOS TARGETARCH VERSION=dev
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/crux ./cmd/crux

FROM alpine:3.22
RUN apk add --no-cache tmux ca-certificates git openssh-client bash \
 && adduser -D -u 1000 crux
COPY --from=build /out/crux /usr/local/bin/crux
USER crux
WORKDIR /home/crux
ENV CRUX_SOCKET=/home/crux/crux.sock
ENTRYPOINT ["crux"]
CMD ["--help"]
