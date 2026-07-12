locals {
  name_prefix = "${var.project}-${var.environment}"

  vpc_id             = data.terraform_remote_state.empi.outputs.vpc_id
  vpc_cidr           = data.terraform_remote_state.empi.outputs.vpc_cidr
  private_subnet_ids = data.terraform_remote_state.empi.outputs.private_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.empi.outputs.public_subnet_ids

  admin_cidrs = length(var.admin_cidrs) > 0 ? var.admin_cidrs : ["${chomp(data.http.myip.response_body)}/32"]

  ecs_execution_role_arn = var.create_iam_roles ? aws_iam_role.execution[0].arn : var.lab_role_arn
}
