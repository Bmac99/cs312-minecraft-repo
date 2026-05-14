#!/usr/bin/env bash
# ── smoke-test-remote.sh ──────────────────────────────────────────────────────
# Remotely verifies that the Minecraft container is healthy on an EC2 instance.
#
# Usage:
#   bash scripts/smoke-test-remote.sh <EC2_PUBLIC_IP> [SSH_KEY_PATH]
#
# Defaults:
#   SSH_KEY_PATH = ~/.ssh/your-key.pem   ← REPLACE or pass as $2
#   SSH_USER     = ec2-user
#   MC_PORT      = 25565

set -euo pipefail

MC_IP="${1:?Usage: $0 <EC2_PUBLIC_IP> [ssh_key_path]}"
SSH_KEY="${2:-${HOME}/.ssh/your-key.pem}"   # ← REPLACE default if needed
SSH_USER="ec2-user"
MC_PORT=25565
CONTAINER_NAME="minecraft"
PASS=0
FAIL=0

pass() { echo "  [✓] $*"; (( PASS++ )) || true; }
fail() { echo "  [✗] $*"; (( FAIL++ )) || true; }

echo ""
echo "══════════════════════════════════════════"
echo "  Minecraft Remote Smoke Test"
echo "  Target : ${MC_IP}"
echo "══════════════════════════════════════════"
echo ""

# ── 1. SSH reachable ──────────────────────────────────────────────────────────
echo "[1/5] Checking SSH connectivity..."
if ssh -i "${SSH_KEY}" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
       "${SSH_USER}@${MC_IP}" "echo ok" &>/dev/null; then
  pass "SSH reachable"
else
  fail "SSH unreachable – check security group and key"
  exit 1
fi

# Helper: run remote command
remote() { ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
                "${SSH_USER}@${MC_IP}" "$@"; }

# ── 2. Docker running ─────────────────────────────────────────────────────────
echo "[2/5] Checking Docker daemon..."
if remote "systemctl is-active docker" &>/dev/null; then
  pass "Docker running"
else
  fail "Docker not running"
fi

# ── 3. Container Up ───────────────────────────────────────────────────────────
echo "[3/5] Checking container status..."
STATUS=$(remote "docker inspect -f '{{.State.Status}}' ${CONTAINER_NAME} 2>/dev/null || echo missing")
if [[ "${STATUS}" == "running" ]]; then
  pass "minecraft container Up"
else
  fail "minecraft container status: ${STATUS}"
fi

# ── 4. Log contains init signal ───────────────────────────────────────────────
echo "[4/5] Polling container logs for 'Done' (up to 3 min)..."
FOUND=false
for i in $(seq 1 36); do
  LOGS=$(remote "docker logs ${CONTAINER_NAME} 2>&1" 2>/dev/null || true)
  if echo "${LOGS}" | grep -qE "Done|Starting Minecraft server"; then
    FOUND=true
    break
  fi
  printf "    waiting... (%ds)\r" $(( i * 5 ))
  sleep 5
done
echo ""
if ${FOUND}; then
  pass "Server says Done (initialized)"
else
  fail "Server did not log 'Done' within 3 minutes"
  echo "  Last 20 log lines:"
  remote "docker logs ${CONTAINER_NAME} 2>&1 | tail -20" || true
fi

# ── 5. Port open ──────────────────────────────────────────────────────────────
echo "[5/5] Checking port ${MC_PORT}..."
if command -v nc &>/dev/null; then
  if nc -zw5 "${MC_IP}" "${MC_PORT}" 2>/dev/null; then
    pass "Port ${MC_PORT} open"
  else
    fail "Port ${MC_PORT} closed – check security group inbound rules"
  fi
else
  echo "  [~] nc not found – skipping port check (install nmap or netcat)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "══════════════════════════════════════════"
echo ""
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
