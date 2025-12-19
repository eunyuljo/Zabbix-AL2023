# Data source for Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Key Pair - Create only if public key file exists
resource "aws_key_pair" "zabbix_key" {
  count      = fileexists("~/.ssh/${var.key_pair_name}.pub") ? 1 : 0
  key_name   = var.key_pair_name
  public_key = file("~/.ssh/${var.key_pair_name}.pub")

  tags = {
    Name = "${var.project_name}-${var.environment}-keypair"
  }
}

# EC2 Instance for Zabbix Server
resource "aws_instance" "zabbix_server" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type              = var.instance_type
  key_name                   = length(aws_key_pair.zabbix_key) > 0 ? aws_key_pair.zabbix_key[0].key_name : var.key_pair_name
  subnet_id                  = aws_subnet.public_subnets[0].id
  vpc_security_group_ids     = [aws_security_group.zabbix_server_sg.id]
  associate_public_ip_address = true
  iam_instance_profile       = aws_iam_instance_profile.zabbix_ec2_profile.name

  # EBS Volume settings
  root_block_device {
    volume_size           = 30
    volume_type          = "gp3"
    encrypted            = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-${var.environment}-server-root-volume"
    }
  }

  user_data = base64encode(templatefile("${path.module}/userdata-simple.sh", {
    mysql_root_password = var.mysql_root_password
    zabbix_db_password  = var.zabbix_db_password
  }))

  tags = {
    Name = "${var.project_name}-${var.environment}-server"
    Type = "ZabbixServer"
  }

  # Ensure internet gateway is created before the instance
  depends_on = [aws_internet_gateway.zabbix_igw]
}