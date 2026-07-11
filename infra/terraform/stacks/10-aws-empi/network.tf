# Red del núcleo EMPI en AWS. Base para RDS/Redis/OpenSearch/MSK/ECS (subredes privadas)
# y para el edge público (subredes públicas). Su CIDR se exporta al stack 40-xcloud-net.
module "network" {
  source = "../../modules/aws-network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = local.this.single_nat_gateway
}
