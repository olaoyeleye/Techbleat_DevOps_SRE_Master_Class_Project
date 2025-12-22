output "vpc_id" {
	description = "ID of the created VPC"
	value       = aws_vpc.main.id
}

output "vpc_cidr" {
	description = "CIDR block of the VPC"
	value       = aws_vpc.main.cidr_block
}

output "vpc_name" {
	description = "Name tag applied to the VPC"
	value       = var.vpc_name
}

output "public_subnet_ids" {
	description = "IDs of the public subnets (public_CYO1, public_CYO2)"
	value       = [for s in aws_subnet.public : s.id]
}

output "public_subnet_names" {
	description = "Names (tags) of the public subnets"
	value       = [for s in aws_subnet.public : s.tags["Name"]]
}

output "private_subnet_ids" {
	description = "IDs of the private subnets (private_CYO1, private_CYO2)"
	value       = [for s in aws_subnet.private : s.id]
}

output "private_subnet_names" {
	description = "Names (tags) of the private subnets"
	value       = [for s in aws_subnet.private : s.tags["Name"]]
}

output "internet_gateway_id" {
	description = "ID of the internet gateway"
	value       = aws_internet_gateway.main.id
}

output "region" {
	description = "Region used for deployment"
	value       = var.aws_region
}