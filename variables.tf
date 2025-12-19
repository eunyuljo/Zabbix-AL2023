variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "zabbix"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b"]
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
  default     = "zabbix-key"
}

variable "zabbix_db_password" {
  description = "Zabbix database password"
  type        = string
  default     = "Zabbix-P@ssw0rd123"
  sensitive   = true
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  default     = "aprkwhsWkd!2"
  sensitive   = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Zabbix"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # 운영환경에서는 특정 IP로 제한 권장
}