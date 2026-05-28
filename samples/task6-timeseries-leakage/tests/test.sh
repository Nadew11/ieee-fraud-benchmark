#!/usr/bin/env bash
set -uo pipefail
mkdir -p /logs/verifier
LOG="/logs/verifier/details.txt"
REWARD="/logs/verifier/reward.txt"
log() { echo "$1" | tee -a "$LOG"; }
log "=== Task 6 Verifier — $(date -u) ==="

python3 - <<'PYEOF' 2>&1 | tee -a "$LOG"
import os

passed = 0; total = 5
auc = None
method_text = ""

# CHECK 1: auc.txt valid
if os.path.exists("/output/auc.txt"):
    try:
        auc = float(open("/output/auc.txt").read().strip())
        print(f"PASS [1/5] auc.txt = {auc:.4f}")
        passed += 1
    except Exception as e:
        print(f"FAIL [1/5] auc.txt parse error: {e}")
else:
    print("FAIL [1/5] /output/auc.txt not found")

# CHECK 2: AUC not leaked (if agent used random split or computed features
# on full dataset before split, AUC inflates above 0.88)
if auc is not None:
    leaked_threshold = 0.88
    if auc <= leaked_threshold:
        print(f"PASS [2/5] AUC {auc:.4f} <= {leaked_threshold} (not obviously leaked)")
        passed += 1
    else:
        print(f"FAIL [2/5] AUC {auc:.4f} > {leaked_threshold} — "
              f"suspiciously high. Features likely computed on full dataset "
              f"before split, or random split used instead of temporal.")

# CHECK 3: methodology.txt exists and mentions temporal/chronological approach
if os.path.exists("/output/methodology.txt"):
    method_text = open("/output/methodology.txt").read().lower()
    temporal_keywords = ["temporal", "time-based", "chronological", "sort",
                         "past", "historical", "transactiondt", "before",
                         "future", "production"]
    hits = [kw for kw in temporal_keywords if kw in method_text]
    if len(hits) >= 2:
        print(f"PASS [3/5] methodology.txt references temporal concepts: {hits[:4]}")
        passed += 1
    else:
        print(f"FAIL [3/5] methodology.txt lacks temporal awareness (found: {hits}). "
              f"Must explain why time-ordering matters for this data.")
else:
    print("FAIL [3/5] /output/methodology.txt not found")

# CHECK 4: methodology does NOT describe random split as primary strategy
if method_text:
    random_indicators = ["random split", "random shuffle", "shuffle the data",
                         "randomly selected"]
    temporal_indicators = ["temporal", "time-based", "chronological",
                           "first 80%", "last 20%", "sorted by time",
                           "sorted by transactiondt"]
    mentions_random = any(kw in method_text for kw in random_indicators)
    mentions_temporal = any(kw in method_text for kw in temporal_indicators)

    if mentions_temporal and not mentions_random:
        print(f"PASS [4/5] Methodology describes temporal split correctly")
        passed += 1
    elif mentions_temporal and mentions_random:
        print(f"PASS [4/5] Methodology describes temporal split (random keyword likely a parameter name)")
        passed += 1
    elif mentions_random and not mentions_temporal:
        print(f"FAIL [4/5] Methodology describes RANDOM split on time-series data. "
              f"Random splits leak future patterns into training data.")
    else:
        print(f"FAIL [4/5] Methodology does not clearly describe split strategy")

# CHECK 5: AUC above floor (model trained successfully, not random guessing)
if auc is not None:
    floor = 0.62
    if auc >= floor:
        print(f"PASS [5/5] AUC {auc:.4f} above floor {floor} — model trained")
        passed += 1
    else:
        print(f"FAIL [5/5] AUC {auc:.4f} below floor {floor} — "
              f"model failed to train or features were all null/wrong")

score = 1.0 if passed == total else 0.0
print(f"\nSCORE: {passed}/{total} — reward: {score}")
open("/logs/verifier/py_score.txt", "w").write(str(score))
PYEOF

final=$(cat /logs/verifier/py_score.txt 2>/dev/null || echo "0.0")
echo "$final" > "$REWARD"
log "=== Final reward: $final ==="
