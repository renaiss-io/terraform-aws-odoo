import boto3
import json
import os 

# Create a Boto3 client for Image Builder
imagebuilder = boto3.client('imagebuilder')
PIPELINE_ARN = os.environ.get('IMG_BUILDER_ARN')

def lambda_handler(event, context):
    print(event)
    response = imagebuilder.start_image_pipeline_execution(
            imagePipelineArn=PIPELINE_ARN)
    print(response)
