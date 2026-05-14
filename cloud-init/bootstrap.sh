#!/bin/bash
set -e
# Install git, python3, pip, ansible bootstrap
yum update -y
yum install -y git python3
python3 -m pip install --upgrade pip
python3 -m pip install ansible boto3
# Create mountpoint for /data and mount the attached EBS
mkdir -p /data
# Wait for /dev/xvdf to appear and mount it
for i in $(seq 1 20); do
  if [ -b /dev/xvdf ]; then
    break
  fi
  sleep 3
done
if [ -b /dev/xvdf ]; then
  mkfs -t ext4 /dev/xvdf || true
  mount /dev/xvdf /data || true
  echo "/dev/xvdf /data ext4 defaults,nofail 0 2" >> /etc/fstab
fi
# Clone repo (assumes repo is public or uses deploy key)
cd /home/ec2-user
git clone https://github.com/your-org/your-minecraft-repo.git /home/ec2-user/minecraft-setup || true
chown -R ec2-user:ec2-user /home/ec2-user/minecraft-setup
