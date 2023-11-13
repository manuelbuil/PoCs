terraform {
    required_version = ">=0.12"
    required_providers {
        aws = {
        source  = "hashicorp/aws"
        version = "~>3.0"
        }
    }
}

provider "aws" {
    region = var.region
    access_key = var.access_key
    secret_key = var.secret_key
}

resource "aws_vpc" "vpc" {
    cidr_block = "10.11.0.0/16"
    tags = {
        Name = "rke2-k3s-networking"
    }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "mbuil-igw"
  }
}

resource "aws_default_route_table" "myRouter" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id


  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "mbuil-default-route"
  }

}

resource "aws_subnet" "dualStack-subnet" {
    vpc_id = aws_vpc.vpc.id
    cidr_block = "10.11.0.0/24"
    map_public_ip_on_launch = true
}

resource "aws_network_interface" "myInterface" {
  subnet_id   = aws_subnet.dualStack-subnet.id
  
  //security group
  security_groups = [aws_security_group.allow_ssh.id]
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description      = "SSH from VPC"
    to_port          = 22
    from_port        = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_instance" "foo" {
  ami           = "ami-03486abd2962c176f"
  instance_type = "t3.medium"

  network_interface {
    network_interface_id = aws_network_interface.myInterface.id
    device_index         = 0
  }

  key_name = "mbuil"

  root_block_device {
    volume_size = 20
    volume_type = "standard"
  }

  tags = {
    Name = "mbuil-terraform"
  }
}

output "vpc_id" {
    value = aws_vpc.vpc.id
}

output "subnet_id" {
    value = aws_subnet.dualStack-subnet.id
}

output "publicIP" {
    value = aws_instance.foo.public_ip
}
