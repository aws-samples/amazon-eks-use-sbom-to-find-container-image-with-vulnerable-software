from kubernetes import client, config
import boto3
import os
import json

def main():
    bucket_name = os.environ['S3_BUCKET_NAME']
    cluster_name = os.environ['EKS_CLUSTER_NAME']
    config.load_incluster_config()
    # Get list of all images running on cluster
    v1 = client.CoreV1Api()
    pods = v1.list_pod_for_all_namespaces(watch=False)
    images = {}
    for pod in pods.items:
        for container in pod.spec.containers:
            image = container.image
            namespace = pod.metadata.namespace
            podname = pod.metadata.name
            if image not in images:
                i = image.split(":")
                images[image] = {
                    'image_name': image,
                    'repo_name': i[0],
                    'pods': []
                }
            images[image]['pods'].append({
                'podname': podname,
                'namespace': namespace
            })

    # Upload list of images to S3
    s3client = boto3.client('s3')
    key = "eks-running-images/" + cluster_name + '-image-list.json'
    print('writing image list json to bucket ' + bucket_name)
    jsonBody = []
    for item in images.values():
        jsonBody.append(json.dumps(item) + '\n')
    s3client.put_object(
        Body=''.join(jsonBody),
        Bucket=bucket_name, 
        Key=key
    )

    print('image list written to S3 bucket with key ' + key)

if __name__ == '__main__':
    main()