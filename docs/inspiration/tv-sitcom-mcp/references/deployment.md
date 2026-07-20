# Deployment

## Docker
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
EXPOSE 41208
CMD ["python", "scripts/tv_mcp_server.py", "--federation", "http://federation:41207"]
```

## Systemd
```ini
[Unit]
Description=TV Sitcom MCP Server
After=network.target

[Service]
Type=simple
User=agent
WorkingDirectory=/opt/tv-sitcom-mcp
ExecStart=/opt/tv-sitcom-mcp/.venv/bin/python scripts/tv_mcp_server.py --federation http://localhost:41207
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

## Environment Variables
- `TV_MCP_PORT` (default 41208)
- `TV_MCP_HOST` (default 0.0.0.0)
- `FEDERATION_URL` (default http://localhost:41207)
