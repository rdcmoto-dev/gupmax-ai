FROM python:3.14.0-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app
COPY requirements.staging.txt ./
RUN pip install --no-cache-dir -r requirements.staging.txt
COPY pyproject.toml ./
RUN pip install --no-cache-dir --no-deps .
COPY . ./

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
