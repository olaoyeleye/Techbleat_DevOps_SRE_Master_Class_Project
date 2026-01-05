terraform {
  backend "s3" {
    bucket  = "techbleat-terraform-state-cynwumoye"
    key     = "cynwumoye/terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }
}
