FROM python:3.11-slim

# Install dependencies
RUN pip install --no-cache-dir pandas==2.1.4 scikit-learn==1.4.0 xgboost==2.0.3 numpy==1.26.3

# Create directories
RUN mkdir -p /data /output /logs/verifier /workspace

# Copy data generation + injection script
COPY data/source_identity.csv /setup/source_identity.csv
COPY data/generate_data.py /setup/generate_data.py

# Generate the messy dataset at build time
RUN python /setup/generate_data.py && rm -f /data/ground_truth.json

# Agent skill hints
COPY skills /root/.claude/skills
COPY skills /root/.gemini/skills
COPY skills /root/.codex/skills
COPY skills /root/.agents/skills
COPY skills /root/.github/skills

WORKDIR /workspace
