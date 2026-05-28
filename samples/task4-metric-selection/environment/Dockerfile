FROM python:3.11-slim
RUN pip install --no-cache-dir pandas==2.1.4 scikit-learn==1.4.0 xgboost==2.0.3 numpy==1.26.3
RUN mkdir -p /data /output /logs/verifier /workspace
COPY data/predictions.csv /data/predictions.csv
COPY data/dataset_info.txt /data/dataset_info.txt
COPY data/draft_evaluation.txt /data/draft_evaluation.txt
COPY data/cost_assumptions.txt /data/cost_assumptions.txt
# Agent skill hints
COPY skills /root/.claude/skills
COPY skills /root/.gemini/skills
COPY skills /root/.codex/skills
COPY skills /root/.agents/skills
COPY skills /root/.github/skills

WORKDIR /workspace
