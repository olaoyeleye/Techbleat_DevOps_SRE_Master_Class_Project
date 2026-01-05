aws_region = "eu-west-1"

vpc_cidr = "10.0.0.0/16"

vpc_name = "CynWumOye_CYO"

public_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
public_subnet_names = ["public_CYO1", "public_CYO2"]

private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_names = ["private_CYO1", "private_CYO2"]
ec2_ami              = "ami-09c54d172e7aa3d9a"
ec2_instance_type    = "t3.micro"
db_admin_password    = "1234abcd"
