# EFS File System for Kafka Data Persistence
resource "aws_efs_file_system" "kafka_data" {
  creation_token = "kafka-data-efs"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name      = "Kafka Data EFS"
    CreatedBy = "Terraform"
    Purpose   = "Kafka persistent storage"
  }
}

# EFS Mount Target in Availability Zone A
resource "aws_efs_mount_target" "kafka_mount_a" {
  file_system_id  = aws_efs_file_system.kafka_data.id
  subnet_id       = aws_subnet.public_subnet_a.id
  security_groups = [aws_security_group.efs_kafka.id]
}

# EFS Mount Target in Availability Zone B
resource "aws_efs_mount_target" "kafka_mount_b" {
  file_system_id  = aws_efs_file_system.kafka_data.id
  subnet_id       = aws_subnet.public_subnet_b.id
  security_groups = [aws_security_group.efs_kafka.id]
}

# Security Group for EFS - Allow NFS access from ECS tasks
resource "aws_security_group" "efs_kafka" {
  name        = "efs-kafka-sg"
  description = "Security group for Kafka EFS mount targets"
  vpc_id      = aws_vpc.base_vpc.id

  ingress {
    description     = "NFS from ECS tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.web_dmz.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "EFS Kafka Security Group"
  }

  lifecycle {
    ignore_changes = [ingress]
  }
}

# Security group rule to allow Kafka service to access EFS
resource "aws_security_group_rule" "kafka_to_efs" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.efs_kafka.id
  source_security_group_id = aws_security_group.kafka_service.id
  description              = "NFS from Kafka service"
}

# CloudWatch Log Group for Kafka Container
resource "aws_cloudwatch_log_group" "kafka_log_group" {
  name              = "kafka-logs"
  retention_in_days = 7

  tags = {
    Name      = "Kafka Logs"
    CreatedBy = "Terraform"
  }
}

# Service Discovery Namespace for internal services
resource "aws_service_discovery_private_dns_namespace" "base_services" {
  name        = "base-services.local"
  description = "Private DNS namespace for base services"
  vpc         = aws_vpc.base_vpc.id

  tags = {
    Name = "Base Services Namespace"
  }
}

# Service Discovery Service for Kafka
resource "aws_service_discovery_service" "kafka" {
  name = "kafka"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.base_services.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name = "Kafka Service Discovery"
  }
}

# Security Group for Kafka Service
resource "aws_security_group" "kafka_service" {
  name        = "kafka-service-sg"
  description = "Security group for Kafka ECS service"
  vpc_id      = aws_vpc.base_vpc.id

  ingress {
    description     = "Kafka broker port from ECS tasks"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.web_dmz.id]
  }

  ingress {
    description = "Kafka controller port (internal)"
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Kafka Service Security Group"
  }
}

# ECS Task Definition for Kafka
resource "aws_ecs_task_definition" "kafka_task" {
  family                   = "kafka"
  execution_role_arn       = aws_iam_role.ecs_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]

  # EFS Volume for Kafka Data Persistence
  volume {
    name = "kafka-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.kafka_data.id
      transit_encryption = "ENABLED"

      authorization_config {
        iam = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "kafka"
      image     = "confluentinc/cp-kafka:latest"
      cpu       = 512 # CPU units (~25% of t3.small)
      memory    = 768 # Memory in MB (~37.5% of t3.small)
      essential = true

      portMappings = [
        {
          containerPort = 9092
          protocol      = "tcp"
        },
        {
          containerPort = 9093
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "kafka-data"
          containerPath = "/var/lib/kafka/data"
          readOnly      = false
        }
      ]

      environment = [
        {
          name  = "KAFKA_HEAP_OPTS"
          value = "-Xmx512m -Xms512m"
        },
        {
          name  = "KAFKA_LOG_DIRS"
          value = "/var/lib/kafka/data"
        },
        {
          name  = "KAFKA_NODE_ID"
          value = "1"
        },
        {
          name  = "KAFKA_PROCESS_ROLES"
          value = "broker,controller"
        },
        {
          name  = "KAFKA_CONTROLLER_QUORUM_VOTERS"
          value = "1@localhost:9093"
        },
        {
          name  = "KAFKA_LISTENERS"
          value = "PLAINTEXT://0.0.0.0:9092,CONTROLLER://localhost:9093"
        },
        {
          name  = "KAFKA_ADVERTISED_LISTENERS"
          value = "PLAINTEXT://kafka.base-services.local:9092"
        },
        {
          name  = "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"
          value = "PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT"
        },
        {
          name  = "KAFKA_CONTROLLER_LISTENER_NAMES"
          value = "CONTROLLER"
        },
        {
          name  = "KAFKA_INTER_BROKER_LISTENER_NAME"
          value = "PLAINTEXT"
        },
        {
          name  = "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR"
          value = "1"
        },
        {
          name  = "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR"
          value = "1"
        },
        {
          name  = "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR"
          value = "1"
        },
        {
          name  = "KAFKA_AUTO_CREATE_TOPICS_ENABLE"
          value = "true"
        },
        {
          name  = "KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS"
          value = "0"
        },
        {
          name  = "CLUSTER_ID"
          value = "MkU3OEVBNTcwNTJENDM2Qk"
        }
      ]

      healthCheck = {
        command = [
          "CMD-SHELL",
          "kafka-broker-api-versions --bootstrap-server localhost:9092 || exit 1"
        ]
        interval    = 30
        timeout     = 10
        retries     = 5
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.kafka_log_group.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "kafka"
        }
      }
    }
  ])

  tags = {
    Name = "Kafka Task Definition"
  }
}

# ECS Service for Kafka
resource "aws_ecs_service" "kafka_service" {
  name            = "kafka-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  desired_count   = 1
  launch_type     = "EC2"
  task_definition = aws_ecs_task_definition.kafka_task.arn

  network_configuration {
    subnets         = [aws_subnet.public_subnet_a.id]
    security_groups = [aws_security_group.kafka_service.id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.kafka.arn
  }

  # Placement strategy to keep Kafka on the same instance if possible
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  tags = {
    Name = "Kafka ECS Service"
  }
}
