FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN groupadd --system app && useradd --system --gid app --create-home app


FROM base AS development

COPY requirements.txt requirements-dev.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt \
    && pip install --no-cache-dir --requirement requirements-dev.txt

COPY pyproject.toml README.md ./
COPY app ./app
RUN pip install --no-cache-dir --no-deps --editable .

COPY alembic.ini ./
COPY alembic ./alembic
COPY tests ./tests

RUN chown -R app:app /app
USER app

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]


FROM base AS builder

COPY requirements.txt ./
RUN pip wheel --wheel-dir /wheels --requirement requirements.txt

COPY pyproject.toml README.md ./
COPY app ./app
RUN pip wheel --no-deps --wheel-dir /wheels .


FROM base AS runtime

COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir /wheels/* && rm -rf /wheels

COPY alembic.ini ./
COPY alembic ./alembic

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health/live', timeout=2)"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]


FROM development AS test

CMD ["pytest", "-q"]
