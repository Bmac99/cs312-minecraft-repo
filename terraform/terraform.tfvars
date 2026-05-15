aws_region           = "us-west-2"
instance_type        = "t3.medium"
ssh_key_name         = "minecraft-key"
ssh_public_key_path  = "~/.ssh/id_rsa.pub"
admin_cidr           = "0.0.0.0/0"
minecraft_cidr       = "0.0.0.0/0"
data_volume_size_gb  = 50
lab_instance_profile = "LabInstanceProfile"
