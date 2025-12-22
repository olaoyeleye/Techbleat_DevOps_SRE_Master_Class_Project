terraform {
  backend "s3" {
    bucket = "techbleat-terraform-state-CynWumOye"
    key    = "CynWumOye/terraform.tfstate"
    region = "eu-west-1"
    encrypt = true
  }
}
