FROM golang:1.26-alpine3.22 AS build
RUN apk add --no-cache git
WORKDIR /s
COPY go.mod go.sum ./
RUN go mod download
COPY . ./
ENV CGO_ENABLED=0
RUN go generate ./...
RUN go build -tags enableUpgrade -o /mediamtx

FROM bluenviron/mediamtx:latest-ffmpeg
COPY --from=build /mediamtx /mediamtx
