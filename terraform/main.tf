terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC
resource "aws_vpc" "minecraft_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "minecraft-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.minecraft_vpc.id
  cidr_block        = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = { Name = "minecraft-public-subnet" }
}

data "aws_availability_zones" "available" {}

# Internet Gateway and Route Table
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.minecraft_vpc.id
  tags = { Name = "minecraft-igw" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.minecraft_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "minecraft-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group
resource "aws_security_group" "minecraft_sg" {
  name        = "minecraft-sg"
  description = "Allow SSH and Minecraft"
  vpc_id      = aws_vpc.minecraft_vpc.id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Minecraft TCP"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = [var.minecraft_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "minecraft-sg" }
}

# Key pair (assumes public key provided)
resource "aws_key_pair" "admin_key" {
  key_name   = var.ssh_key_name
  public_key = file(var.ssh_public_key_path)
}

# AMI lookup (Amazon Linux 2023)
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# EBS volume for /data
resource "aws_ebs_volume" "data_volume" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = var.data_volume_size_gb
  type              = "gp3"
  tags = { Name = "minecraft-data-volume" }
}

# EC2 instance
resource "aws_instance" "minecraft" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = aws_key_pair.admin_key.key_name
  vpc_security_group_ids = [aws_security_group.minecraft_sg.id]
  associate_public_ip_address = true
  iam_instance_profile   = var.lab_instance_profile
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "minecraft-server" }

  # Attach EBS volume and use cloud-init to create mountpoint and install Ansible bootstrap
  user_data = file("${path.module}/cloud-init/bootstrap.sh")
}

# Attach EBS to instance
resource "aws_volume_attachment" "data_attach" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.data_volume.id
  instance_id = aws_instance.minecraft.id
  force_detach = true
}

output "minecraft_public_ip" {
  value = aws_instance.minecraft.public_ip
}
