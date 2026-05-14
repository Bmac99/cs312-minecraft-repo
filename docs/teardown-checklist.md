# Teardown Checklist

Follow this sequence to avoid data loss and orphaned AWS resources.

## 1 – Final World Backup

Always back up before teardown. Do this first.

```bash
# Option A: Ansible tag
ansible-playbook -i ansible/inventory/hosts.example ansible/playbook.yml \
  --tags backup

# Option B: Script
bash scripts/s3-backup.sh
```

Verify backup landed in S3:
```bash
aws s3 ls s3://your-minecraft-world-bucket/worlds/world/ \
  --region us-west-2 --recursive --human-readable --summarize
```

- [ ] Backup completed without errors
- [ ] S3 object count / total size looks correct

## 2 – Stop the Container (optional – graceful shutdown)

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@<MC_IP> \
  "docker stop minecraft && docker rm minecraft"
```

## 3 – Revoke Active SSH Sessions

```bash
# List connected sessions from the instance
ssh -i ~/.ssh/your-key.pem ec2-user@<MC_IP> "who"
```

Notify any connected players and wait for them to disconnect.

## 4 – Terraform Destroy

```bash
cd terraform/
terraform plan -destroy -out=destroy.plan
terraform apply destroy.plan
```

Resources destroyed (confirm your module includes these):
- [ ] `aws_instance.minecraft` (EC2)
- [ ] `aws_security_group.minecraft`
- [ ] `aws_eip` / `aws_eip_association` (if used)
- [ ] `aws_iam_instance_profile.lab` (if managed by TF)

**Do NOT destroy** (retain for future restore):
- `aws_s3_bucket.minecraft_world` – contains world backups
- `aws_ecr_repository.minecraft` – contains versioned images

## 5 – Revoke GitHub Actions Role (if OIDC)

Only if you are retiring the repository entirely:
```bash
aws iam delete-role-policy \
  --role-name GitHubActionsECRRole \
  --policy-name ECRPushPolicy
aws iam delete-role --role-name GitHubActionsECRRole
```

## 6 – Clean Up Local State

```bash
# Remove generated inventory entry
sed -i 's/ansible_host=.*/ansible_host=<MINECRAFT_PUBLIC_IP>/' \
  ansible/inventory/hosts.example

# Remove Terraform lock file (optional)
rm -f terraform/.terraform.lock.hcl
```

## 7 – Post-Teardown Verification

```bash
# EC2 instance terminated
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=minecraft" \
  --query 'Reservations[].Instances[].State.Name' \
  --region us-west-2
# Expected: ["terminated"]

# S3 backup retained
aws s3 ls s3://your-minecraft-world-bucket/ --region us-west-2
```

- [ ] EC2 instance shows `terminated`
- [ ] S3 bucket and world data intact
- [ ] ECR images intact
- [ ] No unexpected charges in AWS Cost Explorer (check 24 h later)
