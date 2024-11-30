output "existing_vpc_id" {
  value = data.aws_vpc.existing.id
}

output "existing_vpc_cidr" {
  value = data.aws_vpc.existing.cidr_block
}

output "x86_deployment_instance_types" {
  value = local.x86_deployment_instance_types
}

output "arm64_deployment_instance_types" {
  value = local.arm64_deployment_instance_types
}

output "ecr_token_username" {
  value = data.aws_ecrpublic_authorization_token.token.user_name
}

output "ecr_token_password" {
  value = data.aws_ecrpublic_authorization_token.token.password
}