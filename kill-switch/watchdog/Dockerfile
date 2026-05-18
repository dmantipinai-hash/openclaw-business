FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY watchdog.py .

EXPOSE 5000
CMD ["python", "watchdog.py", "--config", "/etc/kill-switch/gateways.json"]
