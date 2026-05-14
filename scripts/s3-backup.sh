#!/usr/bin/env bash
# ── s3-backup.sh ──────────────────────────────────────────────────────────────
# Backs up the live Minecraft world to S3 with a brief container stop for
# consistency. Restarts the container automatically when done.
#
# Designed to run ON the EC2 instance (e.g. via cron or Ansible --tags backup).
#
# Usage (on EC2):
#   bash scripts/s3-backup.sh
#
# Or via SSH from workstation:
#   ssh -i ~/.ssh/your-key.pem ec2-user@<MC_IP> 'bash -s' < scripts/s3-backup.sh
#
# Environment overrides:
#   S3_BUCKET        (default: your-minecraft-world-bucket)  ← REPLACE
#   S3_PREFIX        (default: worlds/world)
#   AWS_REGION       (default: us-west-2)
#   DATA_DIR         (default: /data)
#   CONTAINER_NAME   (default: minecraft)

set -euo pipefail

S3_BUCKET="${S3_BUCKET:-your-minecraft-world-bucket}"   # ← REPLACE
S3_PREFIX="${S3_PREFIX:-worlds/world}"
AWS_REGION="${AWS_REGION:-us-west-2}"
DATA_DIR="${DATA_DIR:-/data}"
CONTAINER_NAME="${CONTAINER_NAME:-minecraft}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "══════════════════════════════════════════════"
echo "  Minecraft World Backup"
echo "  Started : ${TIMESTAMP}"
echo "  Source  : ${DATA_DIR}/world/"
echo "  Target  : s3://${S3_BUCKET}/${S3_PREFIX}/"
echo "══════════════════════════════════════════════"
echo ""

# ── Stop container for consistent snapshot ────────────────────────────────────
echo "[1/4] Stopping container '${CONTAINER_NAME}'..."
sudo docker stop "${CONTAINER_NAME}"
echo "      Container stopped."

# ── Sync to S3 ────────────────────────────────────────────────────────────────
echo "[2/4] Syncing world to S3..."
aws s3 sync "${DATA_DIR}/world/" \
  "s3://${S3_BUCKET}/${S3_PREFIX}/" \
  --region "${AWS_REGION}" \
  --delete \
  --no-progress

echo "      Sync complete."

# ── Restart container ─────────────────────────────────────────────────────────
echo "[3/4] Restarting container..."
sudo docker start "${CONTAINER_NAME}"
echo "      Container started."

# ── Verify ────────────────────────────────────────────────────────────────────
echo "[4/4] Verifying S3 objects..."
OBJECT_COUNT=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" \
  --region "${AWS_REGION}" --recursive | wc -l)
echo "      Objects in S3 prefix: ${OBJECT_COUNT}"

echo ""
echo "══════════════════════════════════════════════"
echo "  Backup complete at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "══════════════════════════════════════════════"
