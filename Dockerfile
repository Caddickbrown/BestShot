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

# Use gunicorn for production
CMD ["gunicorn", "-b", "0.0.0.0:18473", "-w", "4", "--timeout", "120", "app.main:app"]
