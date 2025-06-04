#!/bin/bash
openssl genrsa -out ../certs/tls.key 4096
#  CA key
openssl genrsa -out ../certs/ca.key 4096
#  CA cert


openssl req -x509 -new -nodes -key ../certs/ca.key -sha256 -days 365 -out ../certs/ca.crt \
  -subj "/CN=infraops.michael.io"

# CSR config SANs
openssl req -new -key ../certs/tls.key -out ../certs/tls.csr \
   -subj "/CN=infraops.michael.io" \
   -addext "subjectAltName=DNS:infraops-service.michael.io,DNS:infraops-service.michael.io.svc,DNS:infraops-service.michael.io.svc.cluster.local,DNS:infraops-service.default.svc,DNS:infraops-service.default.svc.cluster.local,IP:127.0.0.1,IP:10.211.55.2"

#

echo "subjectAltName=DNS:infraops-service.michael.io,DNS:infraops-service.michael.io.svc,DNS:infraops-service.michael.io.svc.cluster.local,DNS:infraops-service.default.svc,DNS:infraops-service.default.svc.cluster.local,IP:127.0.0.1,IP:10.211.55.2" > ../certs/san.cnf


openssl x509 -req -in ../certs/tls.csr -CA ../certs/ca.crt -CAkey ../certs/ca.key -CAcreateserial \
  -out ../certs/tls.crt -days 365 -sha256 \
  -extfile ../certs/san.cnf

cat ../certs/ca.crt | base64 > ../certs/caBundle.txt

# if run in cluster
# kubectl create secret tls extended-api-tls --cert=../certs/tls.crt --key=../certs/tls.key -n default
