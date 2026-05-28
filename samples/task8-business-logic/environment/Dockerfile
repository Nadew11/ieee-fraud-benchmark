FROM python:3.11-slim
RUN pip install --no-cache-dir pandas==2.1.4 numpy==1.26.3 openpyxl==3.1.5
RUN mkdir -p /data /output /logs/verifier /workspace
COPY data/transactions.csv /data/transactions.csv
COPY data/region_map.csv /data/region_map.csv
COPY data/fx_rates.csv /data/fx_rates.csv
COPY data/fee_schedule.csv /data/fee_schedule.csv
COPY data/ground_truth.json /data/ground_truth.json
# Agent skill hints
COPY skills /root/.claude/skills
COPY skills /root/.gemini/skills
COPY skills /root/.codex/skills
COPY skills /root/.agents/skills
COPY skills /root/.github/skills

WORKDIR /workspace
