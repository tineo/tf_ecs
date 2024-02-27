provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "mi_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "mi-vpc"
  }
}

resource "aws_subnet" "mi_subnet_publica_a" {
  vpc_id            = aws_vpc.mi_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "mi-subnet-publica"
  }
}

resource "aws_subnet" "mi_subnet_publica_b" {
  vpc_id            = aws_vpc.mi_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "mi-subnet-publica"
  }
}

resource "aws_security_group" "mi_sg" {
  name        = "mi-sg"
  description = "Mi grupo de seguridad para ECS"
  vpc_id      = aws_vpc.mi_vpc.id

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


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mi-sg"
  }
}

resource "aws_ecs_cluster" "mi_cluster_ecs" {
  name = "mi-cluster-ecs"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Effect    = "Allow"
        Sid       = ""
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_ecr_repository" "mi_repositorio_ecr" {
  name = "challenge"
}

# CloudWatch
resource "aws_cloudwatch_log_group" "mi_grupo_de_logs" {
  name = "/ecs/mi-aplicacion"
}

resource "aws_ecs_task_definition" "mi_tarea" {
  family                   = "mi-aplicacion"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "mi-contenedor"
      image     = "${data.aws_ecr_repository.mi_repositorio_ecr.repository_url}:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 8080  # Puerto interno del contenedor
          hostPort      = 8080    # Puerto accesible desde fuera
          protocol      = "tcp"
        }
      ]
    logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.mi_grupo_de_logs.name
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_lb" "mi_alb" {
  name               = "mi-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.mi_sg.id]
  subnets            = [aws_subnet.mi_subnet_publica_a.id, aws_subnet.mi_subnet_publica_b.id]

  enable_deletion_protection = false
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.mi_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mi_tg.arn
  }
}

resource "aws_lb_target_group" "mi_tg" {
  name     = "mi-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.mi_vpc.id
  target_type = "ip" 

  health_check {
    enabled = true
    protocol           = "HTTP"
    path               = "/"  # Ajusta esto según el endpoint de salud de tu aplicación
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 60
    interval            = 90
    matcher             = "200"
  }
}

resource "aws_ecs_service" "mi_servicio_ecs" {
  name            = "mi-servicio-ecs"
  cluster         = aws_ecs_cluster.mi_cluster_ecs.id
  task_definition = aws_ecs_task_definition.mi_tarea.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.mi_subnet_publica_a.id]
    security_groups = [aws_security_group.mi_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.mi_tg.arn
    container_name   = "mi-contenedor"
    container_port   = 8080
  }

}

# Crear una Internet Gateway
resource "aws_internet_gateway" "mi_igw" {
  vpc_id = aws_vpc.mi_vpc.id

  tags = {
    Name = "mi-igw"
  }
}

# Crear una ruta por defecto en la tabla de rutas de la VPC que apunte hacia la Internet Gateway
resource "aws_route_table" "mi_ruta_table" {
  vpc_id = aws_vpc.mi_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mi_igw.id
  }

  tags = {
    Name = "mi-ruta-table"
  }
}

# Asociar la tabla de rutas a la subred
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.mi_subnet_publica_a.id
  route_table_id = aws_route_table.mi_ruta_table.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.mi_subnet_publica_b.id
  route_table_id = aws_route_table.mi_ruta_table.id
}


