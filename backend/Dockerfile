FROM python:3.12-slim

# Install system dependencies including terraform and kubectl
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg unzip ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform
RUN curl -fsSL https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_linux_amd64.zip -o /tmp/tf.zip \
    && unzip /tmp/tf.zip -d /usr/local/bin/ \
    && rm /tmp/tf.zip

# Install kubectl
RUN curl -fsSL "https://dl.k8s.io/release/v1.30.2/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Install Helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create data directory for SQLite
RUN mkdir -p /app/data /app/terraform-workspaces

# Copy application code
COPY . .

# Non-root user
RUN useradd -r -u 1001 -g root cloudops \
    && chown -R cloudops:root /app
USER cloudops

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
