module "ecr-pipeline" {
  source                 = "./modules/ecr-pipeline"
  s3_bucket_name         = var.s3_bucket_name
  ecr_repo_name          = var.ecr_repo_name
  codebuild_project_name = var.codebuild_project_name
}

module "data-pipeline" {
  source         = "./modules/data-pipeline"
  s3_bucket_name = module.ecr-pipeline.s3_bucket_name_unique
  s3_kms_key = module.ecr-pipeline.s3_kms_key_arn
}
