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
# Updated Public Subnets (Changed count to 2)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  # This picks a different AZ for each subnet:
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.vpc_name}-public-${count.index}"
    "kubernetes.io/role/elb"                    = "1"        # Required for Public LBs
    "kubernetes.io/cluster/${var.vpc_name}-cluster" = "shared"
  }
}

# Updated Private Subnets (Changed count to 2)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                                        = "${var.vpc_name}-private-${count.index}"
    "kubernetes.io/role/internal-elb"           = "1"        # Required for Private LBs
    "kubernetes.io/cluster/${var.vpc_name}-cluster" = "shared"
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
    count          = 1
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
    count          = 1
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
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 8080
        to_port     = 8080
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 5432
        to_port     = 5432
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

# Generate SSH keypair for instance access
resource "tls_private_key" "deployer" {
    algorithm = "RSA"
    rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
    key_name   = "${var.vpc_name}-deployer-key"
    public_key = tls_private_key.deployer.public_key_openssh
}

# EC2 Instances in Public Subnet
resource "aws_instance" "public" {
    count           = 0
    ami             = var.ec2_ami
    instance_type   = var.ec2_instance_type
    subnet_id       = aws_subnet.public[count.index].id
    vpc_security_group_ids = [aws_security_group.public.id, aws_security_group.internal.id]
    key_name        = aws_key_pair.deployer.key_name

    tags = {
        Name = "${var.vpc_name}-public-instance-${count.index + 1}"
    }
}

# EC2 Instances in Private Subnet
resource "aws_instance" "private" {
    count           = 0
    ami             = var.ec2_ami
    instance_type   = var.ec2_instance_type
    subnet_id       = aws_subnet.private[count.index].id
    vpc_security_group_ids = [aws_security_group.private.id, aws_security_group.internal.id]

    tags = {
        Name = "${var.vpc_name}-private-instance-${count.index + 1}"
    }
}

# Data source to get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
    most_recent = true
    owners      = ["amazon"]

    filter {
        name   = "name"
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }

    filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }
}

# Jenkins Server in Public Subnet
resource "aws_instance" "jenkins" {
    ami                         = data.aws_ami.amazon_linux_2.id
    instance_type               = var.ec2_instance_type
    subnet_id                   = aws_subnet.public[0].id
    vpc_security_group_ids      = [aws_security_group.public.id, aws_security_group.internal.id]
    key_name                    = aws_key_pair.deployer.key_name
    associate_public_ip_address = true

 
user_data = <<-EOF
            #!/bin/bash
            set -x
            exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
            
            echo "Starting Jenkins Installation"
            
            sudo yum update -y
            sudo yum install java-17-amazon-corretto-devel git -y
            java -version
            sudo yum install maven -y

            sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
            sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
            sudo yum install jenkins -y
            sudo systemctl daemon-reload
            sudo systemctl enable jenkins
            sudo systemctl start jenkins

            sudo amazon-linux-extras install docker -y
            sudo systemctl start docker
            sudo systemctl enable docker

            sudo usermod -aG docker jenkins
            sudo chmod 666 /var/run/docker.sock         
            


            # 1. Download the kubectl binary (Linux x86-64)
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

            # 2. Make it executable
            chmod +x ./kubectl

            # 3. Move it to a folder in your PATH
            sudo mv ./kubectl /usr/local/bin/kubectl

            # 4. Verify installation
            kubectl version --client


            echo "Waiting for Jenkins to initialize..."
            for i in {1..60}; do
                if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
                    break
                fi
                sleep 5
            done
            
            if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
                PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
                JENKINS_PASSWORD=$(cat /var/lib/jenkins/secrets/initialAdminPassword)
                echo "Jenkins Initial Admin Password: $JENKINS_PASSWORD" | sudo tee /home/ec2-user/jenkins-password.txt
                echo "Access at: http://$PUBLIC_IP:8080" | sudo tee -a /home/ec2-user/jenkins-password.txt
                sudo chown ec2-user:ec2-user /home/ec2-user/jenkins-password.txt
            fi
            
            echo "Jenkins installation completed!"
            EOF

    tags = {
        Name = "${var.vpc_name}-jenkins"
    }

    depends_on = [aws_internet_gateway.main]
}


# 1. Create a DB Subnet Group (RDS needs to know which subnets to use)
resource "aws_db_subnet_group" "postgres" {
  name       = "cynwumoye_cyo-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.vpc_name}-db-subnet-group"
  }
}

# 2. Create the PaaS Postgres Instance (RDS)
resource "aws_db_instance" "postgres" {
  identifier            = "cynwumoye-cyo-db"
  instance_class        = "db.t3.micro" # Free Tier eligible
  allocated_storage     = 20
  engine                = "postgres"
  engine_version        = "14" # Matches your previous version
  username              = "postgres"
  password              = var.db_admin_password
  db_subnet_group_name  = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.private.id] # Reuse your private SG
  
  db_name               = "cynwumoye_DB"
  skip_final_snapshot   = true # Set to false for production to keep backups
  publicly_accessible   = false # Keeps it secure inside the VPC

  tags = {
    Name = "${var.vpc_name}-postgres-rds"
  }
}

# Nginx Server in Public Subnet
resource "aws_instance" "nginx" {
    ami                         = data.aws_ami.amazon_linux_2.id
    instance_type               = var.ec2_instance_type
    subnet_id                   = aws_subnet.public[0].id
    vpc_security_group_ids      = [aws_security_group.public.id, aws_security_group.internal.id]
    key_name                    = aws_key_pair.deployer.key_name
    associate_public_ip_address = true

    user_data = <<-EOF
                #!/bin/bash
                exec > >(tee /var/log/user-data.log)
                exec 2>&1
                
                echo "Starting Nginx installation..."
                
                # Update system
                sudo yum update -y
                
                # Install Nginx
                sudo amazon-linux-extras install nginx1 -y
                
                # Create custom landing page
                sudo bash -c 'cat > /usr/share/nginx/html/index.html' <<'HTML'
                <!DOCTYPE html>
                <html>
                <head>
                    <title>Welcome to Nginx</title>
                    <style>
                        body { 
                            font-family: Arial, sans-serif; 
                            margin: 50px; 
                            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                            color: white;
                        }
                        .container { 
                            background: rgba(255,255,255,0.95); 
                            padding: 40px; 
                            border-radius: 12px; 
                            box-shadow: 0 8px 32px rgba(0,0,0,0.2);
                            color: #333;
                            max-width: 600px;
                            margin: 0 auto;
                        }
                        h1 { color: #667eea; margin-top: 0; }
                        .status { 
                            background: #e8f5e9; 
                            padding: 20px; 
                            border-radius: 8px; 
                            margin: 20px 0;
                            border-left: 4px solid #4caf50;
                        }
                        .status p { margin: 8px 0; }
                        .success { color: #4caf50; font-weight: bold; }
                    </style>
                </head>
                <body>
                    <div class="container">
                        <h1>✓ Nginx Server Running</h1>
                        <div class="status">
                            <p><strong>Server:</strong> ${var.vpc_name}-nginx</p>
                            <p class="success">Status: Active and Healthy</p>
                            <p><strong>Region:</strong> ${var.aws_region}</p>
                        </div>
                        <p>This page confirms that Nginx has been successfully installed and is serving content.</p>
                    </div>
                </body>
                </html>
                HTML
                
                # Start Nginx
                sudo systemctl enable nginx
                sudo systemctl start nginx
                
                # Check if Nginx is running
                sudo systemctl status nginx
                
                echo "Nginx installation completed!"
                EOF

    tags = {
        Name = "${var.vpc_name}-nginx"
    }

    depends_on = [aws_internet_gateway.main]
}

resource "aws_instance" "backend_server" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.private.id, aws_security_group.internal.id]
  key_name                    = aws_key_pair.deployer.key_name
  associate_public_ip_address = true
user_data = <<-EOF
              #!/bin/bash
              # Log output to check for errors later
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

              echo "Starting Backend Setup..."

              # 1. Update system and install Python 3
              yum update -y
              yum install -y python3 pip

              # 2. Create a directory for the app
              mkdir -p /home/ec2-user/app
              cd /home/ec2-user/app

              # 3. Install FastAPI and Uvicorn
              # We use --user or a venv, but for simple user_data, direct pip is common:
              pip3 install fastapi uvicorn

              # 4. Create a basic 'Hello World' FastAPI app to test port 8000
              cat << 'INNER_EOF' > main.py
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"Status": "Backend is Running on Port 8000"}
INNER_EOF

              # 5. Fix permissions for ec2-user
              chown -R ec2-user:ec2-user /home/ec2-user/app

              # 6. Start the server in the background
              # Note: 0.0.0.0 is required to accept external traffic
              sudo -u ec2-user /usr/local/bin/uvicorn main:app --host 0.0.0.0 --port 8000 &
              
              echo "FastAPI Setup Complete"
              EOF
  tags = {
    Name = "${var.vpc_name}-backend-server"
  }

  depends_on = [aws_internet_gateway.main]
}