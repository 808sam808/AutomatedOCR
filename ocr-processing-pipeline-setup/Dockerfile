FROM python:3.12-slim

LABEL maintainer="OCR Pipeline"
LABEL description="Image OCR watcher with Ollama + Groq classification"

# Prevent Python from writing .pyc files and enable unbuffered output
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY OCR/ /app/OCR/

# Create watch folder
RUN mkdir -p /app/watch_folder

# Expose web dashboard port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import requests; requests.get('http://localhost:8080/api/status', timeout=3)" || exit 1

# Run the script
CMD ["python", "/app/OCR/python_script.py"]
