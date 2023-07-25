output "eks_irsa_policy" {
  value = module.ecr-pipeline.eks_irsa_policy
}

output "s3_bucket_name_unique" {
  value = module.ecr-pipeline.s3_bucket_name_unique
}