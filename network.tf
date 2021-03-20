variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}

resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.prod-vpc.id}"
}

#route table

resource "aws_route_table" "prod-rt" {
  vpc_id = "${aws_vpc.prod-vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id 
  }

  route {
    ipv6_cidr_block = "::/0"
    egress_only_gateway_id = "${aws_egress_only_internet_gateway.gw.id}"
  }

  tags = {
    Name = "prod-rt"
  }
}

#subnet

resource "aws_subnet" "subnet-1" {
  vpc_id = "${aws_vpc.prod-vpc.id}"
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod-subnet-1"
  }
}

resource "aws_route_table_association" "subnet-1-rt" {
  subnet_id = "${aws_subnet.subnet-1.id}"
  route_table_id = "${aws_route_table.prod-rt.id}"
}

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = "${aws_vpc.prod-vpc.id}"

  ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
     
  }

  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
     
  }

  ingress {
    description      = "ssh"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
     
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

resource "aws_network_interface" "prod-eni" {
  subnet_id = "${aws_subnet.subnet-1.id}"
  private_ips = ["10.0.1.50"]
  security_groups = ["${aws_security_group.allow_tls.id}"] 
 
}

resource "aws_eip" "prod-eip" {
  vpc = true
  network_interface = aws_network_interface.prod-eni.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}

#ubuntu
resource "aws_instance" "web-server" {
  ami = "ami-04505e74c0741db8d"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "mainkeytf"

  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.prod-eni.id
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo bash -c '> /var/www/html/index.html'
              EOF

  tags = {
    Name = "prod-web-server"
  }
}
