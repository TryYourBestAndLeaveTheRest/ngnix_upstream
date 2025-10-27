# Blue/Green Deployment with Nginx Auto-Failover

This project implements a Blue/Green deployment strategy with automatic failover using Nginx as a reverse proxy. The setup ensures zero-downtime during service failures by automatically switching from the primary (Blue) service to the backup (Green) service.

## Architecture

```
Client Request → Nginx (port 8080) → Blue Service (port 8081, primary)
                                   └→ Green Service (port 8082, backup)
```

### Key Features

- **Automatic Failover**: Nginx automatically switches to Green when Blue fails
- **Zero Downtime**: Client requests are retried transparently during failover
- **Health Monitoring**: Aggressive health checks for quick failure detection
- **Header Forwarding**: Application headers (`X-App-Pool`, `X-Release-Id`) are preserved
- **Configurable**: Easily switch active pool via environment variables

## Prerequisites

- Docker
- Docker Compose
- `curl` (for testing)

## Quick Start

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd nginx_upstream
```

### 2. Configure Environment

Copy the example environment file:

```bash
cp .env.example .env
```

The `.env` file contains:
- `BLUE_IMAGE` - Docker image for Blue service
- `GREEN_IMAGE` - Docker image for Green service
- `RELEASE_ID_BLUE` - Release identifier for Blue
- `RELEASE_ID_GREEN` - Release identifier for Green
- `ACTIVE_POOL` - Active pool (`blue` or `green`)
- `PORT` - Internal application port (default: 3000)

### 3. Start Services

```bash
docker-compose up -d
```

This will start:
- **Nginx** on `http://localhost:8080`
- **Blue Service** on `http://localhost:8081`
- **Green Service** on `http://localhost:8082`

### 4. Verify Deployment

Check that services are running:

```bash
docker-compose ps
```

## Testing

### Baseline Test (Normal Operation)

Test that Blue is serving requests:

```bash
curl -i http://localhost:8080/version
```

Expected response:
```
HTTP/1.1 200 OK
X-App-Pool: blue
X-Release-Id: v1.0-blue
...
```

### Failover Test

#### Step 1: Trigger Chaos on Blue

Simulate Blue service failure:

```bash
curl -X POST http://localhost:8081/chaos/start?mode=error
```

#### Step 2: Verify Automatic Failover

Send requests to Nginx (they should now go to Green):

```bash
curl -i http://localhost:8080/version
```

Expected response:
```
HTTP/1.1 200 OK
X-App-Pool: green
X-Release-Id: v1.0-green
...
```

#### Step 3: Continuous Testing

Test that all requests succeed during failover:

```bash
for i in {1..20}; do
  curl -s http://localhost:8080/version | grep -E "X-App-Pool|X-Release-Id"
  sleep 0.5
done
```

All requests should return `200 OK` with Green headers.

#### Step 4: Stop Chaos

Restore Blue service:

```bash
curl -X POST http://localhost:8081/chaos/stop
```

### Manual Pool Switch

To manually switch the active pool, edit `.env`:

```bash
# Change ACTIVE_POOL from blue to green
ACTIVE_POOL=green
```

Then restart:

```bash
docker-compose down
docker-compose up -d
```

## Endpoints

### Main Service (via Nginx - port 8080)

- `GET /version` - Returns version info with pool and release headers
- `GET /healthz` - Health check endpoint

### Direct Service Access

**Blue Service (port 8081):**
- `GET http://localhost:8081/version`
- `POST http://localhost:8081/chaos/start?mode=error` - Simulate errors
- `POST http://localhost:8081/chaos/start?mode=timeout` - Simulate timeouts
- `POST http://localhost:8081/chaos/stop` - End simulation
- `GET http://localhost:8081/healthz`

**Green Service (port 8082):**
- Same endpoints as Blue, accessible on port 8082

## Configuration Details

### Nginx Failover Settings

- **max_fails**: 2 (mark server down after 2 failures)
- **fail_timeout**: 5s (server stays down for 5 seconds)
- **proxy_connect_timeout**: 2s
- **proxy_read_timeout**: 2s
- **proxy_send_timeout**: 2s
- **retry policy**: Retries on error, timeout, and 5xx responses

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `BLUE_IMAGE` | Docker image for Blue service | `yimikaade/wonderful:devops-stage-two` |
| `GREEN_IMAGE` | Docker image for Green service | `yimikaade/wonderful:devops-stage-two` |
| `RELEASE_ID_BLUE` | Release ID for Blue | `v1.0-blue` |
| `RELEASE_ID_GREEN` | Release ID for Green | `v1.0-green` |
| `ACTIVE_POOL` | Active pool name | `blue` or `green` |
| `PORT` | Internal app port | `3000` |

## Troubleshooting

### Check Container Logs

```bash
# Nginx logs
docker-compose logs nginx

# Blue service logs
docker-compose logs app_blue

# Green service logs
docker-compose logs app_green
```

### Check Nginx Configuration

```bash
docker-compose exec nginx cat /etc/nginx/nginx.conf
```

### Test Direct Service Access

```bash
# Test Blue directly
curl http://localhost:8081/version

# Test Green directly
curl http://localhost:8082/version
```

### Restart Services

```bash
docker-compose down
docker-compose up -d
```

## How It Works

1. **Normal Operation**: All traffic goes to the active pool (Blue by default)
2. **Failure Detection**: When Blue fails (timeout or 5xx), Nginx marks it as down
3. **Automatic Retry**: Failed requests are automatically retried to Green
4. **Transparent Failover**: Clients still receive 200 OK responses
5. **Recovery**: After `fail_timeout` (5s), Nginx checks if Blue has recovered

## Project Structure

```
.
├── docker-compose.yml       # Service orchestration
├── Dockerfile.nginx         # Custom Nginx image
├── nginx.conf.template      # Nginx configuration template
├── entrypoint.sh           # Nginx startup script
├── .env                    # Environment variables (do not commit)
├── .env.example            # Example environment file
└── README.md               # This file
```

## CI/CD Integration

This setup is designed to work with automated grading/CI systems:

1. CI sets environment variables in `.env`
2. Runs `docker-compose up -d`
3. Tests baseline operation
4. Triggers chaos on active pool
5. Verifies automatic failover with zero failed requests

## Performance Expectations

- **Failover Time**: < 5 seconds
- **Request Success Rate**: 100% (zero failures allowed)
- **Active Pool Accuracy**: ≥95% of requests to correct pool

## Cleanup

Stop and remove all containers:

```bash
docker-compose down
```

Remove volumes and images:

```bash
docker-compose down -v
docker rmi $(docker images -q nginx_upstream_nginx)
```

## License

This project is for educational purposes as part of the DevOps Intern Stage 2 Task.
