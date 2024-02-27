provider "aws" {
  region = "us-east-1"
}

# Crea una Virtual Private Cloud (VPC) con un bloque CIDR 10.0.0.0/16
# habilita el soporte DNS y los nombres de host DNS, y la etiqueta con el nombre "mi-vpc".
resource "aws_vpc" "mi_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "mi-vpc"
  }
}
# Estas subredes definen dos áreas separadas dentro de la VPC en diferentes zonas de disponibilidad (us-east-1a y us-east-1b) para alta disponibilidad
# ambas configuradas para asignar IPs públicas a instancias lanzadas dentro de ellas y etiquetadas como "mi-subnet-publica".
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
# Crea un grupo de seguridad para controlar el acceso a los recursos dentro de la VPC. 
# Permite tráfico entrante en los puertos 80 y 8080 (HTTP y un puerto personalizado) y permite todo el tráfico saliente.
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
  ingress {
    from_port   = 443
    to_port     = 443
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
# Se define un clúster ECS llamado "mi-cluster-ecs" donde se ejecutarán las tareas y servicios de contenedores.
resource "aws_ecs_cluster" "mi_cluster_ecs" {
  name = "mi-cluster-ecs"
}
# Crea un rol IAM para la ejecución de tareas de ECS y adjunta la política de rol estándar de AWS para la ejecución de tareas de ECS, 
# permitiendo que las tareas asuman este rol para interactuar con otros servicios de AWS.
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
# Recupera la información de un repositorio de Amazon Elastic Container Registry (ECR) existente llamado "challenge".
# El cual se ha creado en el otro repo github
data "aws_ecr_repository" "mi_repositorio_ecr" {
  name = "challenge"
}

# Crea un grupo de logs en Amazon CloudWatch para almacenar los logs de las aplicaciones que se ejecutan en los contenedores.
resource "aws_cloudwatch_log_group" "mi_grupo_de_logs" {
  name = "/ecs/mi-aplicacion"
}

# Define una tarea ECS para la aplicación, incluyendo configuración como el rol de ejecución, la red, los recursos de CPU y memoria
# y la definición del contenedor, que usa una imagen del repositorio ECR, configura mapeo de puertos y especifica la configuración de logs.
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

# Crea un balanceador de carga de aplicaciones (ALB), un oyente para el ALB que escucha en el puerto 80
# y un grupo objetivo para el ALB que especifica en qué puerto deben recibir las instancias el tráfico, junto con una comprobación de salud.
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
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.mi_certificado_acm.arn

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
    path               = "/"  
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 60
    interval            = 90
    matcher             = "200"
  }
}

# Define un servicio ECS que especifica cómo se debe ejecutar la tarea definida anteriormente en el clúster ECS
# incluyendo la configuración de red y cómo debe interactuar con el ALB.

resource "aws_ecs_service" "mi_servicio_ecs" {
  name            = "mi-servicio-ecs"
  cluster         = aws_ecs_cluster.mi_cluster_ecs.id
  task_definition = aws_ecs_task_definition.mi_tarea.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.mi_subnet_publica_a.id, aws_subnet.mi_subnet_publica_b.id]
    security_groups = [aws_security_group.mi_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.mi_tg.arn
    container_name   = "mi-contenedor"
    container_port   = 8080
  }

}

# Crea una Internet Gateway para la VPC, una tabla de rutas que incluye una ruta por defecto para dirigir el tráfico hacia la Internet Gateway
# y asocia esta tabla de rutas con las subredes públicas para permitir el acceso a Internet.

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

# Crear un certificado ACM
resource "aws_acm_certificate" "mi_certificado_acm" {
  domain_name       = "challenge.makinap.com"
  validation_method = "DNS"

  tags = {
    Name = "mi-certificado-acm"
  }

  lifecycle {
    create_before_destroy = true
  }
}

