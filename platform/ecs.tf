# Create an ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs-cluster" # Name of the ECS cluster
}

# IAM Role for ECS Service
# This role allows ECS to assume the role and interact with other AWS services.
resource "aws_iam_role" "ecs_service_role" {
  name = "ecsServiceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs.amazonaws.com" # ECS Service
        },
        Action = ["sts:AssumeRole"],
      },
    ],
  })
}

# IAM Policy for ECS Service Role
# Attach a policy that grants permissions for ECS Service to interact with other AWS services.
resource "aws_iam_role_policy_attachment" "ecs_service_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole" # Policy for ECS Service
  role       = aws_iam_role.ecs_service_role.name                                   # Attach to ECS service role
}

# IAM Role for EC2 Instances
# This role allows EC2 instances to assume the role and interact with ECS.
resource "aws_iam_role" "ec2_role" {
  name = "ec2Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com" # EC2 Service
        },
        Action = ["sts:AssumeRole"],
      },
    ],
  })
}

# IAM Instance Profile for EC2 Instances
# Connects an instance profile to the EC2 role, used to manage permissions for ECS EC2 instances.
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs_instance_profile"
  role = aws_iam_role.ec2_role.name # Reference the EC2 role
}

# IAM Policy for EC2 Role
# Attach a policy that allows EC2 instances to interact with ECS.
resource "aws_iam_role_policy_attachment" "ecs_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
  role       = aws_iam_role.ec2_role.name # Attach to EC2 role
}

# IAM Policy for SSM
resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2_role.name # Attach to EC2 role
}

# Launch Configuration for AutoScaling Group
# Defines the EC2 launch configuration for ECS instances with SSM support.
resource "aws_launch_configuration" "app_launch_config_with_ssm" {
  name_prefix          = "app-launch-config-with-ssm-"                      # Use name_prefix instead of name for create_before_destroy
  image_id             = "ami-0af9e559c6749eb48"                            # Amazon Machine Image (AMI)
  instance_type        = "t3.small"                                         # Instance type (2GB RAM, ~$15/month)
  security_groups      = [aws_security_group.web_dmz.id]                    # Security group for the instances
  iam_instance_profile = aws_iam_instance_profile.ecs_instance_profile.name # Instance profile for EC2
  # User data to set ECS cluster
  user_data = <<-EOF
    #!/bin/bash
    sudo yum install -y amazon-ssm-agent
    sudo systemctl start amazon-ssm-agent
    sudo systemctl enable amazon-ssm-agent

    sudo dnf install -y ec2-instance-connect
    echo ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.id} >> /etc/ecs/ecs.config
  EOF

  lifecycle {
    create_before_destroy = true
  }
}

# AutoScaling Group
# AutoScaling group to manage ECS instances.
resource "aws_autoscaling_group" "ecs_autoscaling" {
  vpc_zone_identifier  = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id] # Subnets for the ASG
  min_size             = 1                                                              # Minimum number of instances
  max_size             = 1                                                              # Maximum number of instances
  desired_capacity     = 1                                                              # Desired number of instances
  launch_configuration = aws_launch_configuration.app_launch_config_with_ssm.name       # Reference the launch config
  tag {
    key                 = "Name"
    value               = "ECS AutoScaling Group"
    propagate_at_launch = true
  }
}

# IAM Role for ECS Task Execution
# This role allows ECS tasks to assume roles for executing containers.
resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = ["ecs-tasks.amazonaws.com"] # ECS Tasks
      },
      Action = ["sts:AssumeRole"],
    }],
  })
}

# IAM Policy for ECS Task Execution
# This policy grants ECS tasks permissions to interact with CloudWatch Logs and other services.
resource "aws_iam_role_policy_attachment" "ecs_task_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" # Policy for ECS tasks
  role       = aws_iam_role.ecs_task_role.name                                         # Attach to ECS task role
}
