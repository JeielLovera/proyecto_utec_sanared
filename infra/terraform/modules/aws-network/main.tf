# =============================================================================
# módulo aws-network — VPC del núcleo EMPI
# Subredes públicas (edge) + privadas (datos/cómputo) en N AZs, IGW, NAT, y
# endpoints de gateway (S3/DynamoDB, gratis) para tráfico privado a servicios AWS.
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs     = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  nat_qty = var.single_nat_gateway ? 1 : var.az_count
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}

# ---------------------------------------------------------------------------
# Subredes
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.name_prefix}-public-${local.azs[count.index]}"
    tier = "public"
  }
}

resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 100)
  availability_zone = local.azs[count.index]
  tags = {
    Name = "${var.name_prefix}-private-${local.azs[count.index]}"
    tier = "private"
  }
}

# ---------------------------------------------------------------------------
# Internet Gateway + rutas públicas
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# NAT Gateway(s) + rutas privadas (salida a internet para pull de imágenes, etc.)
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = local.nat_qty
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-eip-nat-${count.index}" }
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_qty
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.name_prefix}-nat-${count.index}" }
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-rt-private-${count.index}" }
}

resource "aws_route" "private_nat" {
  count                  = var.az_count
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  # Si single_nat_gateway, todas las privadas apuntan al NAT[0].
  nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ---------------------------------------------------------------------------
# Gateway endpoints (S3/DynamoDB) — tráfico privado sin costo de datos
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  tags              = { Name = "${var.name_prefix}-vpce-s3" }
}

data "aws_region" "current" {}
