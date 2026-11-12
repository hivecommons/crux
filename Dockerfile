# ghcr.io/hivecommons/crux — the crux binary plus tmux, which the runtime
# drives to host agent processes. Built by goreleaser (.goreleaser.yaml) from
# the already cross-compiled binary for each platform; `docker build` from a
# checkout works too via the builder stage.
#
# The Go base is a literal FROM, not an ARG: Dependabot's docker ecosystem
# (.github/dependabot.yml) only sees literal image references, and nothing
# passes a --build-arg for the builder image anyway.
FROM --platform=$BUILDPLATFORM golang:1.26-alpine@sha256:30b1e546a9c7fa3b747c2bdba3a0c7bdf3a02ebb4c5b8405d2f948d7e8aac4ec AS build
ARG TARGETOS TARGETARCH VERSION=dev
WORKDIR /src
COPY go.mod go.sum ./
RUN for i in 1 2 3; do go mod download && break; [ "$i" = 3 ] && exit 1; sleep $((i * 2)); done
COPY . .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/crux ./cmd/crux

FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf
RUN apk add --no-cache tmux ca-certificates git openssh-client bash \
 && adduser -D -u 1000 crux
COPY --from=build /out/crux /usr/local/bin/crux
USER crux
WORKDIR /home/crux
ENV CRUX_SOCKET=/home/crux/crux.sock
ENTRYPOINT ["crux"]
CMD ["--help"]
