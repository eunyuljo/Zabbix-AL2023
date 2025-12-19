# IAM Role for EC2 to access SSM
resource "aws_iam_role" "zabbix_ec2_ssm_role" {
  name = "${var.project_name}-${var.environment}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-ssm-role"
  }
}

# Attach AWS managed SSM policy to the role
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.zabbix_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Optional: CloudWatch Agent policy for enhanced monitoring
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  role       = aws_iam_role.zabbix_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom policy for additional permissions (if needed)
resource "aws_iam_role_policy" "zabbix_custom_policy" {
  name = "${var.project_name}-${var.environment}-custom-policy"
  role = aws_iam_role.zabbix_ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Instance Profile for the EC2 instance
resource "aws_iam_instance_profile" "zabbix_ec2_profile" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.zabbix_ec2_ssm_role.name

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-profile"
  }
}