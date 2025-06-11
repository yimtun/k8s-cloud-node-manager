# Build stage
FROM golang:1.23.3 AS builder

# Set working directory
WORKDIR /app

# Copy go.mod and go.sum first for better caching
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o k8s-cloud-node-manager apiserver.go

# Runtime stage
FROM alpine:3.19

# Install ca-certificates for HTTPS support
RUN apk --no-cache add ca-certificates libcap

# Create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Set working directory
WORKDIR /app

# Copy binary from builder stage
COPY --from=builder /app/k8s-cloud-node-manager .

# Copy certificates directory
COPY --from=builder /app/certs ./certs

# Change ownership to non-root user
RUN chown -R appuser:appgroup k8s-cloud-node-manager certs

# Add capability to bind to privileged ports
RUN setcap 'cap_net_bind_service=+ep' k8s-cloud-node-manager

# Switch to non-root user
USER appuser

# Expose port 443 for HTTPS
EXPOSE 443

# Set environment variable to use 443 port
ENV PORT=443

# Run the application
CMD ["./k8s-cloud-node-manager"]

# docker build . -t yimtune/k8s-cloud-node-manager:v0.2