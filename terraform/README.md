# SBOM-ECR-BLOG


## Modules  

In this repoistory there are 2 sub modules which are deployed at the same time via the main.tf file located at the root directory.

1. Data-pipeline Module

In this module the tools required to stand up the athena database is deployed. This module deploys an aws glue catalogue database, a glue table, a glue crawler, the required iam role and athena workgroup.


2. ECR-Pipeline Module

This module is used to deploy the CodeBuild pipeline to generate SBOM whenever a new image is pushed to any ECR repository in the account. The module also creates EventBridge rule that triggers CodeBuild when a new image is pushed. It also creates a CodeBuild pipeline to generate SBOM for existing images stored in any ECR repository in the account. S3 bucket is also created to store the generated SBOM files.
  

## Deployment steps for Terraform modules
  

1. Edit terraform.tfvars file inside terraform directory with any text editor of your choice. Make sure you provide the correct value for aws_region variable to specify the AWS region where you want to deploy. You can accept the defaults for other variables or change them if you wish to.

2. Make sure the principal being used to run terraform has necessary privileges to deploy all resources. Refer to [terraform documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) for providing AWS authentication credentials.

3. Confirm you have configured the default region on your AWS CLI, run:

	```
	aws configure list
	```

   The recommended way to provide AWS credentials and default region is to use environment variables. For example, you can use AWS_PROFILE environment variable to provide the AWS CLI profile to use for running terraform. Refer to AWS CLI documentation for configuration details.  

 4. Once these steps are complete please run the following from inside the terraform directory:
 - Initialize your working directory
	```
    terraform init
	```
 - Preview the resources that terraform will deploy in your AWS account

	```
	terraform plan
	```
- Deploy the resources. By running the following and selecting yes when prompted to approve the creation of resources

	```
	terraform apply
	```
