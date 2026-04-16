
resource "aws_route_table" "public_routes" {
  vpc_id = aws_vpc.base_vpc.id

  tags = {
    Name = "Public Routes"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_routes.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_routes.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public_routes.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.base_igw.id
}

resource "aws_network_acl" "public_subnet_acl" {
  vpc_id = aws_vpc.base_vpc.id
  tags = {
    Name = "PublicSubnetAcl"
  }
}

resource "aws_network_acl_rule" "http_ingress_acl" {
  network_acl_id = aws_network_acl.public_subnet_acl.id
  rule_number    = 100
  rule_action    = "allow"
  from_port      = 80
  to_port        = 80
  protocol       = "tcp"
  cidr_block     = "0.0.0.0/0"
  egress         = false
}

resource "aws_network_acl_rule" "https_ingress_acl" {
  network_acl_id = aws_network_acl.public_subnet_acl.id
  rule_number    = 200
  rule_action    = "allow"
  from_port      = 443
  to_port        = 443
  protocol       = "tcp"
  cidr_block     = "0.0.0.0/0"
  egress         = false
}

resource "aws_network_acl_rule" "ssh_ingress_acl" {
  network_acl_id = aws_network_acl.public_subnet_acl.id
  rule_number    = 300
  rule_action    = "allow"
  from_port      = 22
  to_port        = 22
  protocol       = "tcp"
  cidr_block     = "0.0.0.0/0"
  egress         = false
}

resource "aws_network_acl_rule" "ephemeral_ports_ingress_acl" {
  network_acl_id = aws_network_acl.public_subnet_acl.id
  rule_number    = 400
  rule_action    = "allow"
  from_port      = 1024
  to_port        = 65535
  protocol       = "tcp"
  cidr_block     = "0.0.0.0/0"
  egress         = false
}

resource "aws_network_acl_rule" "https_egress_acl" {
  network_acl_id = aws_network_acl.public_subnet_acl.id
  rule_number    = 100
  rule_action    = "allow"
  from_port      = 443
  to_port        = 443
  protocol       = "tcp"
  cidr_block     = "0.0.0.0/0"
  egress         = true
}

resource "aws_network_acl_rule" "ephemeral_ports_egress_acl" {
  network_acl_id = aws_network_acl.public_subnet_acl.id
  rule_number    = 200
  rule_action    = "allow"
  from_port      = 1024
  to_port        = 65535
  protocol       = "tcp"
  cidr_block     = "0.0.0.0/0"
  egress         = true
}

resource "aws_network_acl_rule" "http_egress_acl" {
  network_acl_id = aws_network_acl.public_subnet_acl.id
  rule_number    = 300
  rule_action    = "allow"
  from_port      = 80
  to_port        = 80
  protocol       = "tcp"
  cidr_block     = "0.0.0.0/0"
  egress         = true
}

resource "aws_network_acl_association" "public_subnet_a_acl_association" {
  network_acl_id = aws_network_acl.public_subnet_acl.id
  subnet_id      = aws_subnet.public_subnet_a.id
}

resource "aws_network_acl_association" "public_subnet_b_acl_association" {
  network_acl_id = aws_network_acl.public_subnet_acl.id
  subnet_id      = aws_subnet.public_subnet_b.id
}
