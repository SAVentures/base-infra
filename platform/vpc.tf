data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "base_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name         = "BaseVPC"
    "Created By" = "Shubhanshu"
  }
}

resource "aws_internet_gateway" "base_igw" {
  vpc_id = aws_vpc.base_vpc.id

  tags = {
    Name         = "BaseIGW"
    "Created By" = "Shubhanshu"
  }
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.base_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-A"
    Type = "Public"
  }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.base_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-B"
    Type = "Public"
  }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id                  = aws_vpc.base_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "Private-A"
    Type = "Private"
  }
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id                  = aws_vpc.base_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "Private-B"
    Type = "Private"
  }
}

resource "aws_db_subnet_group" "my_subnet_group" {
  name       = "my-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]

  tags = {
    Name = "db subnet group"
  }
}
