#!/bin/bash
# =============================================================================
# CERTIFICATE GENERATION SCRIPT
# =============================================================================
# This script generates self-signed SSL certificates for HTTPS support.

# Set variables
CERT_DIR="certs"
CERT_FILE="$CERT_DIR/ssl.crt"
KEY_FILE="$CERT_DIR/ssl.key"
DAYS=365
SUBJECT="/C=US/ST=State/L=City/O=Organization/CN=dr-demo"

# Create the certs directory if it doesn't exist
mkdir -p "$CERT_DIR"

# Generate a self-signed certificate
echo "Generating self-signed certificate..."
openssl req -x509 -nodes -days $DAYS -newkey rsa:2048 \
  -keyout "$KEY_FILE" -out "$CERT_FILE" \
  -subj "$SUBJECT"

# Set appropriate permissions
chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

echo "Certificate generation complete!"
echo "Certificate: $CERT_FILE"
echo "Private key: $KEY_FILE"
echo "Validity: $DAYS days"



