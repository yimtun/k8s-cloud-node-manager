# build image
FROM golang:1.23.3 AS builder

#
WORKDIR /app

# copy go.mod and  go.sum
COPY go.mod go.sum ./

#
RUN go mod download

# copy code
COPY . .

# build
RUN CGO_ENABLED=0 GOOS=linux go build -o metadata-apiserver apiserver.go

#
FROM alpine:3.19

#  install ca-certificates
RUN apk --no-cache add ca-certificates

#
WORKDIR /app

#
COPY --from=builder /app/metadata-apiserver .


#
CMD ["./metadata-apiserver"]
