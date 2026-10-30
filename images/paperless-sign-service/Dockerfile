FROM python:3.15.2-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
COPY requirements.txt /tmp/requirements.txt
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install -r /tmp/requirements.txt

FROM python:3.15.2-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"
RUN groupadd --gid 1000 app \
    && useradd --uid 1000 --gid 1000 --no-create-home --shell /usr/sbin/nologin app \
    && install -d -o 1000 -g 1000 -m 0700 /app/data
COPY --from=builder /opt/venv /opt/venv
WORKDIR /app
# Never copy upstream data/: it can contain encrypted tokens and their keys.
COPY app /app/app
COPY LICENSE /usr/share/licenses/paperless-sign-service/LICENSE
USER 1000:1000
EXPOSE 8088
HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=6 \
    CMD ["python", "-c", "import urllib.request as u; assert all(u.urlopen('http://127.0.0.1:8088'+p, timeout=4).status == 200 for p in ('/api/health', '/'))"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8088"]
