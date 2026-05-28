FROM python:3.11-slim
RUN pip install --no-cache-dir pandas==2.1.4 scikit-learn==1.4.0 xgboost==2.0.3 numpy==1.26.3
RUN mkdir -p /data /output /logs/verifier /workspace
COPY data/train_transaction.csv /data/train_transaction.csv
COPY data/pipeline.py /data/pipeline.py
# Agent skill hints
COPY skills /root/.claude/skills
COPY skills /root/.gemini/skills
COPY skills /root/.codex/skills
COPY skills /root/.agents/skills
COPY skills /root/.github/skills

WORKDIR /workspace
