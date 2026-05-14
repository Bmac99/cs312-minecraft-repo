# Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Developer Workstation                        │
│                                                                      │
│  git tag v1.2.3  ──►  GitHub Actions CI  ─────────────────────────► │
│                         (publish-to-ecr.yml)                         │
│                              │                                       │
│                    ┌─────────▼──────────┐                            │
│                    │  OIDC / Secrets    │                            │
│                    │  AWS Auth          │                            │
│                    └─────────┬──────────┘                            │
└──────────────────────────────┼───────────────────────────────────────┘
                               │
          ┌────────────────────▼────────────────────┐
          │           Amazon ECR (us-west-2)         │
          │   your-ecr-repo:<tag>                    │
          └────────────────────┬────────────────────┘
                               │  docker pull (instance profile)
                               │
          ┌────────────────────▼────────────────────┐
          │           EC2 Instance                   │
          │  IAM role: LabInstanceProfile            │
          │                                          │
          │  ┌───────────────────────────────────┐  │
          │  │  Docker (minecraft container)      │  │
          │  │  Image  : <ecr_registry>/<repo>   │  │
          │  │  Port   : 25565                   │  │
          │  │  Volume : /data  ◄────────┐       │  │
          │  │  EULA   : TRUE            │       │  │
          │  │  Restart: unless-stopped  │       │  │
          │  └───────────────────────────┼───────┘  │
          │                              │           │
          │  /data (EBS volume)          │           │
          │  └── world/  ───────────────►│           │
          │                                          │
          └─────────────────┬────────────────────────┘
                            │  aws s3 sync (instance profile)
                            ▼
          ┌────────────────────────────────────────┐
          │        Amazon S3                        │
          │  your-minecraft-world-bucket            │
          │  └── worlds/world/  (world archive)     │
          └────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Role |
|---|---|
| GitHub Actions | Build/retag container image on tag push; smoke-test; push to ECR |
| Amazon ECR | Immutable container registry; tags map to git tags |
| EC2 Instance | Runs Minecraft container; uses LabInstanceProfile for AWS API access |
| LabInstanceProfile | Grants EC2 permission to pull from ECR and read/write S3 — no static creds |
| Amazon S3 | Durable world backup storage; used for restore on fresh deploy |
| Ansible | Idempotent configuration management; docker install, ECR auth, deploy, backup |

## Data Flow

1. **Publish**: `git tag v1.2.3 && git push --tags` → CI pulls `itzg/minecraft-server:latest`, retags as `<ecr>/<repo>:v1.2.3`, pushes.
2. **Smoke Test**: CI runs the ECR image in GitHub runner, polls logs for `Done`.
3. **Deploy**: `ansible-playbook` SSH into EC2, installs Docker, authenticates to ECR with instance profile, pulls `v1.2.3`, starts container.
4. **Restore** *(optional)*: With `-e restore_from_s3=true`, Ansible syncs `s3://your-minecraft-world-bucket/worlds/world/` → `/data/world/` before container start.
5. **Backup**: Run `--tags backup` or `scripts/s3-backup.sh` to sync `/data/world/` back to S3.

## Terraform Integration

```hcl
# Expected outputs from your Terraform root module:
output "minecraft_public_ip" {
  value = aws_instance.minecraft.public_ip
}

output "ecr_repository_url" {
  value = aws_ecr_repository.minecraft.repository_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.minecraft_world.bucket
}
```

Use them:
```bash
export MC_IP=$(terraform output -raw minecraft_public_ip)
export ECR_URL=$(terraform output -raw ecr_repository_url)
ansible-playbook -i inventory/hosts.example playbook.yml \
  -e "ansible_host=${MC_IP} ecr_registry=${ECR_URL%/*} image_tag=${MINECRAFT_IMAGE_TAG}"
```
