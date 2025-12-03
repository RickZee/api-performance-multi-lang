FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy consumer script
COPY consumer.py .

# Make script executable
RUN chmod +x consumer.py

# Run consumer
CMD ["python", "consumer.py"]




