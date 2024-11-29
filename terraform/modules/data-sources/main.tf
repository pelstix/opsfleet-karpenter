data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

# Instance Type Data Sources
data "aws_ec2_instance_types" "x86_compatible" {
  filter {
    name   = "processor-info.supported-architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "memory-info.size-in-mib"
    values = ["1024", "2048", "4096"]
  }

  filter {
    name   = "vcpu-info.default-vcpus"
    values = ["1", "2", "4", "8"]
  }

  filter {
    name   = "instance-type"
    values = [
      "*.nano", "*.micro", "*.small", "*.medium", "*.large", "*.xlarge",
      "t*", "c*", "m*", "r*"
    ]
  }
}

data "aws_ec2_instance_types" "arm64_compatible" {
  filter {
    name   = "processor-info.supported-architecture"
    values = ["arm64"]
  }

  filter {
    name   = "memory-info.size-in-mib"
    values = ["1024", "2048", "4096"]
  }

  filter {
    name   = "vcpu-info.default-vcpus"
    values = ["1", "2", "4", "8"]
  }

  filter {
    name   = "instance-type"
    values = [
      "*.nano", "*.micro", "*.small", "*.medium", "*.large", "*.xlarge", 
      "c*", "t*", "m*", "r*"
    ]
  }
}

data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["Opsfleet-vpc"]
  }
}

locals {
  x86_instance_types = [for t in data.aws_ec2_instance_types.x86_compatible.instance_types : t 
    if can(regex("^[mtcr]\\d+\\.", t)) || 
       can(regex("^[mtcr]\\d+a\\.", t)) || 
       can(regex("^[mtcr]\\d+i\\.", t))
  ]

  arm64_instance_types = [for t in data.aws_ec2_instance_types.arm64_compatible.instance_types : t 
    if can(regex("^[mtcr]\\d+g\\.", t))
  ]

  x86_deployment_instance_types = slice(
    sort(local.x86_instance_types), 
    0, 
    min(length(local.x86_instance_types), 5)
  )

  arm64_deployment_instance_types = slice(
    sort(local.arm64_instance_types), 
    0, 
    min(length(local.arm64_instance_types), 5)
  )
}