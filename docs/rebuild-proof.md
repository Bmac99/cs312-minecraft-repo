# Rebuild Checklist & Proof Steps

Run through this checklist any time you rebuild the server (new EC2, AMI change, DR drill).

## Pre-flight

- [ ] Terraform apply has completed successfully
- [ ] `terraform output minecraft_public_ip` returns a routable IP
- [ ] SSH key is available at `~/.ssh/your-key.pem`
- [ ] ECR repository contains the target image tag
- [ ] `MINECRAFT_IMAGE_TAG` environment variable is set

```bash
# Verify ECR image exists
aws ecr describe-images \
  --repository-name your-ecr-repo \
  --image-ids imageTag="${MINECRAFT_IMAGE_TAG}" \
  --region us-west-2
```

## Step 1 – Update Inventory

```bash
export MC_IP=$(terraform output -raw minecraft_public_ip)
sed -i "s/<MINECRAFT_PUBLIC_IP>/${MC_IP}/" ansible/inventory/hosts.example
```

## Step 2 – Syntax Check

```bash
cd ansible
ansible-playbook -i inventory/hosts.example playbook.yml \
  -e "image_tag=${MINECRAFT_IMAGE_TAG}" \
  --syntax-check
```

Expected output: `playbook: playbook.yml` (no errors).

## Step 3 – Dry Run

```bash
ansible-playbook -i inventory/hosts.example playbook.yml \
  -e "image_tag=${MINECRAFT_IMAGE_TAG}" \
  --check --diff
```

Review the diff. No actual changes are made.

## Step 4 – Full Deploy (fresh server)

```bash
ansible-playbook -i inventory/hosts.example playbook.yml \
  -e "image_tag=${MINECRAFT_IMAGE_TAG}"
```

### With S3 world restore

```bash
ansible-playbook -i inventory/hosts.example playbook.yml \
  -e "image_tag=${MINECRAFT_IMAGE_TAG} restore_from_s3=true"
```

## Step 5 – Verify Idempotency (re-run proof)

```bash
ansible-playbook -i inventory/hosts.example playbook.yml \
  -e "image_tag=${MINECRAFT_IMAGE_TAG}"
```

✅ **Pass criteria**: Second run reports `changed=0` for all tasks except
`docker_login` (ECR token refresh always re-authenticates) and the `docker_image`
pull task (always checks digest). No task should fail.

## Step 6 – Connectivity Proof

```bash
# Container running
ssh -i ~/.ssh/your-key.pem ec2-user@${MC_IP} \
  "docker ps --filter name=minecraft --format '{{.Status}}'"
# Expected: Up X minutes (healthy)

# Logs show Done
ssh -i ~/.ssh/your-key.pem ec2-user@${MC_IP} \
  "docker logs minecraft 2>&1 | grep -E 'Done|Starting Minecraft server'"

# Port reachable (requires nmap or nc)
nc -zv "${MC_IP}" 25565
# Expected: Connection to <IP> 25565 port [tcp/*] succeeded!
```

## Step 7 – Remote Smoke Test

```bash
bash scripts/smoke-test-remote.sh "${MC_IP}"
```

Expected output:
```
[✓] SSH reachable
[✓] Docker running
[✓] minecraft container Up
[✓] Server says Done
[✓] Port 25565 open
```

## Step 8 – Backup Proof

```bash
ansible-playbook -i inventory/hosts.example playbook.yml --tags backup
# Then verify objects in S3:
aws s3 ls s3://your-minecraft-world-bucket/worlds/world/ --region us-west-2
```
