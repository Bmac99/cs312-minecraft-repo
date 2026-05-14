variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "admin_cidr" {
  type    = string
  default = "203.0.113.0/32" # change to your admin IP
}

variable "minecraft_cidr" {
  type    = string
  default = "0.0.0.0/0" # restrict if desired
}

variable "ssh_key_name" {
  type    = string
  default = "minecraft-key"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "data_volume_size_gb" {
  type    = number
  default = 50
}

variable "lab_instance_profile" {
  type    = string
  description = "Pre-existing instance profile name (LabInstanceProfile)"
  default = "LabInstanceProfile"
}
