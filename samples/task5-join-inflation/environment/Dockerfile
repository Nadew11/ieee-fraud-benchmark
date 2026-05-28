FROM python:3.11-slim
RUN pip install --no-cache-dir pandas==2.1.4 numpy==1.26.3
RUN mkdir -p /data /output /logs/verifier /workspace
COPY data/source_transaction.csv /setup/source_transaction.csv
COPY data/source_identity.csv /setup/source_identity.csv
COPY data/generate_data.py /setup/generate_data.py
RUN python /setup/generate_data.py && rm -f /data/ground_truth.json
# Agent skill hints
COPY skills /root/.claude/skills
COPY skills /root/.gemini/skills
COPY skills /root/.codex/skills
COPY skills /root/.agents/skills
COPY skills /root/.github/skills

WORKDIR /workspace
