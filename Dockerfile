FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/
COPY static/ ./static/
COPY templates/ ./templates/

# Create project directory for media storage
RUN mkdir -p /project

# Set environment variables
ENV PROJECT_ROOT=/project
ENV PORT=18473

EXPOSE 18473

CMD ["python", "app/main.py"]
