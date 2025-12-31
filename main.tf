# main.tf

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
resource "aws_vpc" "main" {
    cidr_block           = var.vpc_cidr
    enable_dns_hostnames = true
    enable_dns_support   = true

    tags = {
        Name = var.vpc_name
    }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${var.vpc_name}-igw"
    }
}

# Public Subnets
resource "aws_subnet" "public" {
    count                   = 2
    vpc_id                  = aws_vpc.main.id
    cidr_block              = var.public_subnet_cidrs[count.index]
    availability_zone       = data.aws_availability_zones.available.names[count.index]
    map_public_ip_on_launch = true

    tags = {
        Name = var.public_subnet_names[count.index]
    }
}

# Private Subnets
resource "aws_subnet" "private" {
    count             = 2
    vpc_id            = aws_vpc.main.id
    cidr_block        = var.private_subnet_cidrs[count.index]
    availability_zone = data.aws_availability_zones.available.names[count.index]

    tags = {
        Name = var.private_subnet_names[count.index]
    }
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main.id
    }

    tags = {
        Name = "${var.vpc_name}-public-rt"
    }
}

# Associate Public Subnets with Route Table
resource "aws_route_table_association" "public" {
    count          = 2
    subnet_id      = aws_subnet.public[count.index].id
    route_table_id = aws_route_table.public.id
}

# Route Table for Private Subnets
resource "aws_route_table" "private" {
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${var.vpc_name}-private-rt"
    }
}

# Associate Private Subnets with Route Table
resource "aws_route_table_association" "private" {
    count          = 2
    subnet_id      = aws_subnet.private[count.index].id
    route_table_id = aws_route_table.private.id
}

# Security Group for Public Instances
resource "aws_security_group" "public" {
    name        = "${var.vpc_name}-public-sg"
    description = "Security group for public instances"
    vpc_id      = aws_vpc.main.id

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 8080
        to_port     = 8080
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "${var.vpc_name}-public-sg"
    }
}

# Security Group for Private Instances
resource "aws_security_group" "private" {
    name        = "${var.vpc_name}-private-sg"
    description = "Security group for private instances"
    vpc_id      = aws_vpc.main.id

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = [var.vpc_cidr]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "${var.vpc_name}-private-sg"
    }
}

# Internal Security Group for inter-instance communication
resource "aws_security_group" "internal" {
    name        = "${var.vpc_name}-internal-sg"
    description = "Allows internal communication within the VPC"
    vpc_id      = aws_vpc.main.id

    ingress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = [var.vpc_cidr]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "${var.vpc_name}-internal-sg"
    }
}

# EC2 Instances in Public Subnet
resource "aws_instance" "public" {
    count           = 2
    ami             = var.ec2_ami
    instance_type   = var.ec2_instance_type
    subnet_id       = aws_subnet.public[count.index].id
    associate_public_ip_address = true
    vpc_security_group_ids       = [aws_security_group.public.id, aws_security_group.internal.id]

    tags = {
        Name = "${var.vpc_name}-public-instance-${count.index + 1}"
    }
}

# EC2 Instances in Private Subnet
resource "aws_instance" "private" {
    count           = 2
    ami             = var.ec2_ami
    instance_type   = var.ec2_instance_type
    subnet_id       = aws_subnet.private[count.index].id
    vpc_security_group_ids = [aws_security_group.private.id, aws_security_group.internal.id]

    tags = {
        Name = "${var.vpc_name}-private-instance-${count.index + 1}"
    }
}

# Jenkins Server in Public Subnet
resource "aws_instance" "jenkins" {
    ami                       = var.ec2_ami
    instance_type             = var.ec2_instance_type
    subnet_id                 = aws_subnet.public[0].id
    associate_public_ip_address = true
    vpc_security_group_ids    = [aws_security_group.public.id, aws_security_group.internal.id]

    user_data = <<-EOF
                #!/bin/bash
                yum update -y
                amazon-linux-extras install java-openjdk11 -y || yum install -y java-11-openjdk
                wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
                rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
                yum install -y jenkins
                systemctl enable jenkins
                systemctl start jenkins
                EOF

    tags = {
        Name = "${var.vpc_name}-jenkins"
    }
}

# Data source for availability zones
data "aws_availability_zones" "available" {
    state = "available"
}

# Postgres DB in Public Subnet
resource "aws_instance" "postgres" {
    ami                       = var.ec2_ami
    instance_type             = var.ec2_instance_type
    subnet_id                 = aws_subnet.public[1].id
    associate_public_ip_address = true
    vpc_security_group_ids    = [aws_security_group.public.id, aws_security_group.internal.id]

    user_data = <<-EOF
                #!/bin/bash
                yum update -y
                amazon-linux-extras install postgresql10 -y || yum install -y postgresql-server
                /usr/bin/postgresql-setup initdb || :
                systemctl enable postgresql
                systemctl start postgresql
                sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"
                EOF

    tags = {
        Name = "${var.vpc_name}-postgres"
    }
}

# Nginx Server in Public Subnet
resource "aws_instance" "nginx" {
    ami                       = var.ec2_ami
    instance_type             = var.ec2_instance_type
    subnet_id                 = aws_subnet.public[1].id
    associate_public_ip_address = true
    vpc_security_group_ids    = [aws_security_group.public.id, aws_security_group.internal.id]

    user_data = <<-EOF
                #!/bin/bash
                yum update -y
                amazon-linux-extras install nginx1 -y || yum install -y nginx
                systemctl enable nginx
                systemctl start nginx
                EOF

    tags = {
        Name = "${var.vpc_name}-nginx"
    }
}



