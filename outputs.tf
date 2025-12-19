# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.zabbix_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.zabbix_vpc.cidr_block
}

# Subnet Outputs
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

# Security Group Outputs
output "zabbix_server_security_group_id" {
  description = "ID of the Zabbix server security group"
  value       = aws_security_group.zabbix_server_sg.id
}

output "zabbix_agent_security_group_id" {
  description = "ID of the Zabbix agent security group"
  value       = aws_security_group.zabbix_agent_sg.id
}

# EC2 Instance Outputs
output "zabbix_server_instance_id" {
  description = "ID of the Zabbix server instance"
  value       = aws_instance.zabbix_server.id
}

output "zabbix_server_public_ip" {
  description = "Public IP address of the Zabbix server"
  value       = aws_instance.zabbix_server.public_ip
}

output "zabbix_server_private_ip" {
  description = "Private IP address of the Zabbix server"
  value       = aws_instance.zabbix_server.private_ip
}

output "zabbix_server_public_dns" {
  description = "Public DNS name of the Zabbix server"
  value       = aws_instance.zabbix_server.public_dns
}

# Zabbix Web Interface URL
output "zabbix_web_url" {
  description = "URL to access Zabbix web interface"
  value       = "http://${aws_instance.zabbix_server.public_ip}/zabbix"
}

# SSH Connection Command
output "ssh_connection_command" {
  description = "SSH command to connect to the Zabbix server"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.zabbix_server.public_ip}"
}

# SSM Session Manager Connection
output "ssm_connection_command" {
  description = "AWS CLI command to connect via Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.zabbix_server.id}"
}

# Installation Information
output "installation_info" {
  description = "Zabbix installation information"
  value = {
    default_username = "Admin"
    default_password = "zabbix"
    web_interface    = "http://${aws_instance.zabbix_server.public_ip}/zabbix"
    ssh_access       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.zabbix_server.public_ip}"
    ssm_access       = "aws ssm start-session --target ${aws_instance.zabbix_server.id}"
    install_log      = "/var/log/zabbix-install.log"
    install_info     = "/home/ec2-user/zabbix-install-info.txt"
  }
}

# Network Information
# IAM Information
output "iam_info" {
  description = "IAM role and instance profile information"
  value = {
    iam_role_name        = aws_iam_role.zabbix_ec2_ssm_role.name
    iam_role_arn         = aws_iam_role.zabbix_ec2_ssm_role.arn
    instance_profile_name = aws_iam_instance_profile.zabbix_ec2_profile.name
    instance_profile_arn  = aws_iam_instance_profile.zabbix_ec2_profile.arn
  }
}

# Network Information
output "network_info" {
  description = "Network configuration information"
  value = {
    vpc_id             = aws_vpc.zabbix_vpc.id
    internet_gateway   = aws_internet_gateway.zabbix_igw.id
    nat_gateway        = aws_nat_gateway.zabbix_nat.id
    public_subnet_az   = aws_subnet.public_subnets[0].availability_zone
    private_subnet_az  = aws_subnet.private_subnets[0].availability_zone
  }
}