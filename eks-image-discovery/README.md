## Overview
This component can be deployed as a scheduled job on any EKS cluster. The job discovers all of the pods running in all namespaces and creates a JSON file with all container images in the pods. The JSON file is uploaded to an S3 bucket configured as an environment variable. A sample JSON would like below
```
{"image_name": "<account_id>.dkr.ecr.us-east-2.amazonaws.com/eks/coredns:v1.8.7-eksbuild.3", "repo_name": "<account_id>.dkr.ecr.us-east-2.amazonaws.com/eks/coredns", "pods": [{"podname": "coredns-5c5677bc78-kns5n", "namespace": "kube-system"}, {"podname": "coredns-5c5677bc78-tjg5j", "namespace": "kube-system"}]}
{"image_name": "<account_id>.dkr.ecr.us-east-2.amazonaws.com/eks/kube-proxy:v1.24.7-minimal-eksbuild.2", "repo_name": "<account_id>.dkr.ecr.us-east-2.amazonaws.com/eks/kube-proxy", "pods": [{"podname": "kube-proxy-5w5nm", "namespace": "kube-system"}, {"podname": "kube-proxy-nmqgc", "namespace": "kube-system"}]}

```

## Deployment steps for EKS cronjob

We assume that you have an existing EKS cluster and kubernetes CLI installed on your machine to interact with the cluster. Perform the steps below to deploy EKS cronjob for discovering running images on your cluster

1. Follow [AWS documentation](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html) to create IAM OIDC provider for the EKS cluster

2. Create IAM role for service account using eksctl. This IAM role will be used by the EKS cronjob to write the list of running container images to S3 bucket. Replace cluster name and policy ARN copied from the Terraform output. The policy is one of the resources created by Terraform modules.

   ```
   eksctl create iamserviceaccount --name image-discovery-job --namespace sbom-image-discovery --cluster <your EKS cluster name> --attach-policy-arn <policy ARN from Terraform output> --approve
   ```

3. Terraform would have created an ECR repository ```eks-image-discovery``` in your account to store image of EKS cronjob. Go to ECR repository in AWS console and click on the button for view push commands. Follow those commands to build and push docker image of EKS cronjob to ECR repository. Copy the image URI of the newly pushed image from AWS console.

4. Navigate to ```config``` directory inside eks-image-discovery. This contains a Kubernetes manifest file that you need to edit for deploying the cronjob. Open ```eks-image-discovery.yaml``` file in any text editor. 

	- Edit image field to change it to image URI that you copied in the previous step.
	- Update the name of S3 bucket in environment variable configuration. Use the bucket name copied from Terraform output
	- Update the name of EKS cluster in environment variable with your cluster name
	- Optionally update the cronjob schedule. By default, the job will run every 5 mins

5. Apply the manifest file using kubectl

   ```
   kubectl apply -f eks-image-discovery.yaml
   ```