provider "aws" {
  region = "ap-south-1"
}

# --- Get default VPC and Subnets ---
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Security Group for EC2 ---
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Allow HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Security Group for ALB ---
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- EC2 Instances ---
resource "aws_instance" "web" {
  count         = 2
  ami           = "ami-0a1235697f4afa8a4" # Replace with your valid AMI
  instance_type = "t2.micro"
  subnet_id     = element(data.aws_subnets.default.ids, count.index)
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum install -y httpd
              echo '<!DOCTYPE html>
              <html>
              <head>
                <title>Instance ${count.index}</title>
                <style>
                  body { font-family: Arial; background-color: ${count.index == 0 ? "#e0f7fa" : "#ffe0b2"}; text-align: center; padding-top: 50px; }
                  h1 { color: #333; }
                </style>
              </head>
              <body>
                <h1>Welcome to EC2 Instance ${count.index}</h1>
                <p>This page is served by instance <strong>${count.index}</strong></p>
              </body>
              </html>' > /var/www/html/index.html
              systemctl enable httpd
              systemctl start httpd
              EOF

  tags = {
    Name = "WebInstance-${count.index}"
  }
}

# --- Load Balancer ---
resource "aws_lb" "alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# --- Target Group ---
resource "aws_lb_target_group" "tg" {
  name        = "web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    path = "/"
    port = "80"
  }
}

# --- Attach EC2s to Target Group ---
resource "aws_lb_target_group_attachment" "tg_attachment" {
  count            = 2
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# --- Listener for ALB ---
resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# --- Output the ALB DNS ---
output "alb_dns" {
  value = aws_lb.alb.dns_name
  description = "Load Balancer DNS - open this in browser to test switching between instances"
}
