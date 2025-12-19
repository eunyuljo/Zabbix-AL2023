# Security Group for Zabbix Server
resource "aws_security_group" "zabbix_server_sg" {
  name        = "${var.project_name}-${var.environment}-server-sg"
  description = "Security group for Zabbix Server"
  vpc_id      = aws_vpc.zabbix_vpc.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # HTTP access for Zabbix Web Interface
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # HTTPS access for Zabbix Web Interface
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Zabbix Server port
  ingress {
    description = "Zabbix Server"
    from_port   = 10051
    to_port     = 10051
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Zabbix Agent port (for monitoring the server itself)
  ingress {
    description = "Zabbix Agent"
    from_port   = 10050
    to_port     = 10050
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # MySQL access (from local only)
  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-server-sg"
  }
}

# Security Group for Zabbix Agents (for future use)
resource "aws_security_group" "zabbix_agent_sg" {
  name        = "${var.project_name}-${var.environment}-agent-sg"
  description = "Security group for Zabbix Agents"
  vpc_id      = aws_vpc.zabbix_vpc.id

  # SSH access (optional)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Zabbix Agent port
  ingress {
    description     = "Zabbix Agent"
    from_port       = 10050
    to_port         = 10050
    protocol        = "tcp"
    security_groups = [aws_security_group.zabbix_server_sg.id]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-agent-sg"
  }
}