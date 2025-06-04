#!/bin/bash

openssl genrsa -out tls.key 4096

openssl req -x509 -new -nodes -key tls.key -sha256 -days 365 -out tls.crt \
  -subj "/CN=infraops.michael.io" \
  -addext "subjectAltName=DNS:infraops-service.michael.io,DNS:infraops-service.michael.io.svc,DNS:infraops-service.michael.io.svc.cluster.local,DNS:infraops-service.default.svc,DNS:infraops-service.default.svc.cluster.local,IP:10.211.55.2"

cat tls.crt | base64 | tr -d '\n'

# if run in cluster
# kubectl create secret tls extended-api-tls --cert=../certs/tls.crt --key=../certs/tls.key -n default
