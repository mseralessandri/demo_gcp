#!/bin/bash

# =============================================================================
# SSL CERTIFICATE GENERATION SCRIPT
# =============================================================================
# This script generates self-signed SSL certificates for the load balancer

set -e

# Create certs directory if it doesn't exist
CERTS_DIR="../terraform/certs"
mkdir -p "$CERTS_DIR"

echo "Generating self-signed SSL certificate..."

# Generate private key
openssl genrsa -out "$CERTS_DIR/ssl.key" 2048

# Generate certificate signing request
openssl req -new -key "$CERTS_DIR/ssl.key" -out "$CERTS_DIR/ssl.csr" -subj "/C=US/ST=CA/L=San Francisco/O=Demo/CN=demo.example.com"

# Generate self-signed certificate
openssl x509 -req -days 365 -in "$CERTS_DIR/ssl.csr" -signkey "$CERTS_DIR/ssl.key" -out "$CERTS_DIR/ssl.crt"

# Clean up CSR file
rm "$CERTS_DIR/ssl.csr"

echo "SSL certificates generated successfully:"
echo "  Private key: $CERTS_DIR/ssl.key"
echo "  Certificate: $CERTS_DIR/ssl.crt"

# Set appropriate permissions
chmod 600 "$CERTS_DIR/ssl.key"
chmod 644 "$CERTS_DIR/ssl.crt"

echo "Certificate generation complete!"
