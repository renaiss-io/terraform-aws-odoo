import boto3
import json
import os

PIPELINE_ARN = os.environ.get("IMG_BUILDER_ARN")
imagebuilder = boto3.client("imagebuilder")


def lambda_handler(event, context):
    print(event)
    response = imagebuilder.start_image_pipeline_execution(
        imagePipelineArn=PIPELINE_ARN
    )
    print(response)
