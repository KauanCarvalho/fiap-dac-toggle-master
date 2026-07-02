FROM python:3.11-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
  gcc \
  libpq-dev \
  && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
  libpq5 \
  && rm -rf /var/lib/apt/lists/*

RUN useradd --no-create-home --shell /bin/false nonroot

WORKDIR /app

COPY --from=builder /install /usr/local
COPY . .

RUN opentelemetry-bootstrap -a install

USER nonroot

EXPOSE 8002

CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8002", "--workers", "2", "--timeout", "30", "app:app"]
