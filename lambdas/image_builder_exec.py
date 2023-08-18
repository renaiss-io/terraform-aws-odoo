import boto3
import json
import os 

def lambda_handler(event, context):

    # Create a Boto3 client for Image Builder
    imagebuilder = boto3.client('imagebuilder')
    pipeline_arn = os.environ.get('IMG_BUILDER_ARN')

    try:
        # Trigger the Image Builder pipeline
        response = imagebuilder.start_image_pipeline_execution(
            imagePipelineArn=pipeline_arn
        )
        
        # Print the response for debugging
        print("Pipeline execution started:", response)
        
        # Construct a response for the Lambda invocation
        lambda_response = {
            "statusCode": 200,
            "body": json.dumps("Image Builder pipeline execution started successfully!")
        }
        
        return lambda_response
    
    except Exception as e:
        # If there's an error, print the error message and construct an error response
        error_message = f"Error starting pipeline execution: {str(e)}"
        print(event)
        print(error_message)
        
        error_response = {
            "statusCode": 500,
            "body": json.dumps(error_message)
        }
        
        return error_response
