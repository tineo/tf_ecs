variable "region" {
  description = "La región de AWS donde se desplegarán los recursos"
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "El bloque CIDR para la VPC"
  default     = "10.0.0.0/16"
}

variable "subnet_public_a_cidr" {
  description = "El bloque CIDR para la subred pública en la zona de disponibilidad a"
  default     = "10.0.1.0/24"
}

variable "subnet_public_b_cidr" {
  description = "El bloque CIDR para la subred pública en la zona de disponibilidad b"
  default     = "10.0.2.0/24"
}

variable "domain_name" {
  description = "El nombre de dominio para el certificado ACM"
  default     = "challenge.makinap.com"
}

