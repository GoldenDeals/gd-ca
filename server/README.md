# CA Server with Caddy

This directory contains the Dockerfile and Caddyfile for a CA server that:
- Serves public certificates and CRLs from a Git repository
- Provides a built-in ACME server for automated certificate issuance
- Uses rate limiting for security
- Uses Let's Encrypt for `gdllc.ru`
- Uses Caddy's built-in ACME server with your custom CA for `gdllc.local` and `gdllc.dev`

## Prerequisites

1. A Git repository containing your public certificates and CRLs in a `public/` directory
2. CA root certificate
3. CA intermediate (department) certificate and key
4. ACME server certificate and key for `acme.gdllc.local` and `acme.gdllc.dev`
5. Docker installed

## Building

```bash
docker build -t ca-server .
```

## Setup

### 1. Create ACME Server Certificates

First, create certificates for the ACME server endpoint:

```bash
# Create certs directory
mkdir -p certs

# Issue certificate for ACME server
cd ..
./scripts/issue_cert.sh local server "acme.gdllc.local" \
  DNS:acme.gdllc.local DNS:acme.gdllc.dev

# Copy to server/certs directory
cp ca/departments/local/certs/acme.gdllc.local__*.cert.pem server/certs/acme-server.cert.pem
cp ca/departments/local/certs/acme.gdllc.local__*.key.pem server/certs/acme-server.key.pem
```

### 2. Update Git Repository URL

Edit `Caddyfile` and replace `YOUR_USERNAME/YOUR_REPO` with your actual Git repository:

```caddyfile
filesystem ca-repo git https://github.com/YOUR_USERNAME/YOUR_REPO.git {
    refresh_period 5m
}
```

## Running

### Using Docker Compose (Recommended)

```bash
docker-compose up -d
```

This will:
- Start Caddy with built-in ACME server
- Serve public certificates and CRLs from Git repository
- Provide ACME endpoints at `acme.gdllc.local` and `acme.gdllc.dev`

### Manual Docker Run

```bash
docker run -d \
  --name ca-server \
  -p 80:80 \
  -p 443:443 \
  -v $(pwd)/../ca/root/root.cert.pem:/etc/caddy/ca/root.cert.pem:ro \
  -v $(pwd)/../ca/departments/local/ca.cert.pem:/etc/caddy/ca/intermediate.cert.pem:ro \
  -v $(pwd)/../ca/departments/local/private/ca.key.pem:/etc/caddy/ca/intermediate.key.pem:ro \
  -v $(pwd)/certs/acme-server.cert.pem:/etc/caddy/ca/acme-server.cert.pem:ro \
  -v $(pwd)/certs/acme-server.key.pem:/etc/caddy/ca/acme-server.key.pem:ro \
  ca-server
```

## Configuration

### Git Repository

Update the Git repository URL in Caddyfile (line 37):

```caddyfile
filesystem ca-repo git https://github.com/YOUR_USERNAME/YOUR_REPO.git {
    refresh_period 5m
}
```

### Rate Limiting

Rate limits are configured per zone:
- Public zone: 60 requests/minute, burst 100
- ACME zone: 30 requests/minute, burst 50
- Internal zone: 100 requests/minute, burst 200

Adjust these values in the Caddyfile based on your needs.

## How It Works

1. **Public CA Server** (`:80`)
   - Serves certificates and CRLs from Git repository
   - Automatically pulls updates every 5 minutes
   - Rate limited to prevent abuse

2. **ACME Server** (`acme.gdllc.local`, `acme.gdllc.dev`)
   - Caddy's built-in ACME server functionality
   - Issues certificates using your intermediate CA
   - ACME directory available at `/acme/internal/directory`

3. **Public Domain** (`gdllc.ru`)
   - Uses Let's Encrypt for certificates
   - Rate limited

4. **Internal Domains** (`gdllc.local`, `gdllc.dev`)
   - Uses Caddy's ACME server with your custom CA
   - Automatically obtains certificates from the ACME server
   - Rate limited

## Using the ACME Server

Other Caddy instances or ACME clients can obtain certificates by pointing to:

```
https://acme.gdllc.local/acme/internal/directory
```

Example Caddyfile for a client:

```caddyfile
{
    acme_ca https://acme.gdllc.local/acme/internal/directory
    acme_ca_root /path/to/root.cert.pem
}

myapp.gdllc.local {
    reverse_proxy localhost:8080
}
```

## Security Notes

- Intermediate CA private key is mounted as read-only volume
- Admin API is disabled (`admin off`)
- Auto HTTPS is disabled for manual control
- Rate limiting is enabled on all endpoints
- Git repository should be private and access-controlled
- ACME server has stricter rate limits than public endpoints

## Volumes

Required volumes:
- `/etc/caddy/ca/root.cert.pem` - Root CA certificate (read-only)
- `/etc/caddy/ca/intermediate.cert.pem` - Intermediate CA certificate (read-only)
- `/etc/caddy/ca/intermediate.key.pem` - Intermediate CA private key (read-only)
- `/etc/caddy/ca/acme-server.cert.pem` - ACME server certificate (read-only)
- `/etc/caddy/ca/acme-server.key.pem` - ACME server private key (read-only)

