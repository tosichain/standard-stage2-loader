# =============================================================================
FROM alpine:3.17.0 AS image-base

RUN apk --no-cache add coreutils xxd

# =============================================================================

FROM golang:1.18 as kubo-build
RUN apt-get update && apt-get install -y llvm 

WORKDIR /app

RUN git clone "https://github.com/tosichain/kubo.git" -b zerolength

WORKDIR /app/kubo
RUN go mod download

COPY ./sys_linux_riscv64.go /go/pkg/mod/github.com/marten-seemann/tcp\@v0.0.0-20210406111302-dfbc87cc63fd/sys_linux_riscv64.go

# =============================================================================
FROM kubo-build as kubo-build-amd64

WORKDIR /app/kubo

RUN GOOS=linux GOARCH=amd64 CGO_ENABLED=0 GOFLAGS="-ldflags=-s-w" make nofuse
RUN llvm-strip -s /app/kubo/cmd/ipfs/ipfs

# =============================================================================
FROM kubo-build as kubo-build-riscv64

WORKDIR /app/kubo

RUN GOOS=linux GOARCH=riscv64 CGO_ENABLED=0 GOFLAGS="-ldflags=-s-w" make nofuse
RUN llvm-strip -s /app/kubo/cmd/ipfs/ipfs

# =============================================================================
FROM golang:1.19 as go-car-build-amd64
RUN apt-get update && apt-get install -y llvm
WORKDIR /app

RUN git clone https://github.com/tosichain/go-car -b v1.0

RUN cd go-car/cmd/car && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "-s -w"
RUN llvm-strip -s /app/go-car/cmd/car/car


# =============================================================================
FROM golang:1.19 as go-car-build-riscv64

WORKDIR /app

RUN apt-get update && apt-get install -y llvm
RUN git clone https://github.com/tosichain/go-car -b v1.0

RUN cd go-car/cmd/car && GOOS=linux GOARCH=riscv64 CGO_ENABLED=0 go build -ldflags "-s -w"
RUN llvm-strip -s /app/go-car/cmd/car/car

# =============================================================================

FROM image-base AS image

WORKDIR /

RUN mkdir -p /opt/amd64/bin /opt/riscv64/bin /opt/ipfs /contract
COPY --from=kubo-build-amd64 "/app/kubo/cmd/ipfs/ipfs" "/opt/amd64/bin/ipfs"
COPY --from=kubo-build-riscv64 "/app/kubo/cmd/ipfs/ipfs" "/opt/riscv64/bin/ipfs"
COPY --from=go-car-build-amd64 "/app/go-car/cmd/car/car" "/opt/amd64/bin/car"
COPY --from=go-car-build-riscv64 "/app/go-car/cmd/car/car" "/opt/riscv64/bin/car"

ENV IPFS_PATH=/opt/ipfs
RUN /opt/amd64/bin/ipfs init --profile=server,flatfs,lowpower -e

COPY ./resolv.conf /etc/resolv.conf 
COPY ./init /init

FROM alpine:3.17.0 AS buildimg
RUN apk add squashfs-tools
COPY --from=image / /image
RUN mksquashfs /image /stage2.squashfs -Xcompression-level 22 -comp zstd -reproducible -all-root -mkfs-time 0 -all-time 0
RUN ls -alR /image
RUN ls -al /stage2.squashfs

FROM busybox
COPY --from=buildimg /stage2.squashfs /stage2.squashfs
