variable "access_key" {}
variable "secret_key" {}
variable "doppler_token" {}
variable "github_token" {}
variable "region" { default = "eu-central-1" }
variable "subnet_id_administration_network" {}
variable "availability_zone" { default = "eu-central-1a" }
variable "instance_type" { default = "t3a.large" }
variable "security_group_id_Admin" {}

# Providerconfiguration
terraform {
  required_providers {
    aws = {
      # TODO: Update to latest version
      source  = "hashicorp/aws"
      version = "4.28.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}

# Data Sources for Instance creation

# check for subnet ID Administration Network
data "aws_subnet" "administration-network" {
  id = var.subnet_id_administration_network
}

# query key pair
data "aws_key_pair" "postrausch-key" {
  key_name = "kubernetes"
}

# query security group admin
data "aws_security_group" "Admin" {
  id = var.security_group_id_Admin
}

# query pub ip for admin
data "aws_eip" "eip-Admin-Server" {
  public_ip = "54.93.162.244"
}

# create interface for admin Server
resource "aws_network_interface" "admin-network-interface" {
  subnet_id   = data.aws_subnet.administration-network.id
  security_groups =  [data.aws_security_group.Admin.id]

  tags = {
    Name = "admin_network_interface"
  }
}

# create aws instance for admin server
resource "aws_instance_request" "Admin-Server" {
  ami           = "ami-0f1793e689f222266" # Debian 11
  instance_type = var.instance_type

# credit specification for overusage
  credit_specification {
    cpu_credits = "standard"
  }

# assign keypair
  key_name = data.aws_key_pair.postrausch-key.key_name

# add name
  tags = {
    Name = "Admin-Server"
  }

# Init Script
user_data = <<EOF
#! /bin/bash
# Doppler Token
export DOPPLER_TOKEN=${var.doppler_token}
# Github Token
export GITHUB_TOKEN=${var.github_token}

# Install Ansible
apt update && apt install -y ansible

#TODO: Implement Ansible Playbook for Admin Server

# pull docker images
docker compose -f /dockerdata/traefik/docker-compose.yml pull

# run docker compose file
docker compose -f /dockerdata/traefik/docker-compose.yml up -d

# log output
output : { all : '| tee -a /var/log/cloud-init-output.log' }
EOF

# add more space for all services
root_block_device {
  volume_size = "80"
  volume_type = "gp3"
  iops = 3000
  throughput = 125
}
}

# assign public ip to aws instance admin-server
resource "aws_eip_association" "eip_assoc-admin-server" {
  # TODO: check if this is the right way to do it
  instance_id   = aws_spot_instance_request.Admin-Server.spot_instance_id
  allocation_id = data.aws_eip.eip-Admin-Server.id
}

# assign network interface to aws instance admin-server
resource "aws_network_interface_attachment" "network-admin-server" {
  # TODO: check if this is the right way to do it
  instance_id          = aws_spot_instance_request.Admin-Server.spot_instance_id
  network_interface_id = aws_network_interface.admin-network-interface.id
  device_index         = 0
}
