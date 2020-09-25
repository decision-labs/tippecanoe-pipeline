# Terraform configuration that creates an AWS lambda for reading an S3 bucket and running a geoprocessing pipeline on it

variable "aws_region" {
  default = "us-west-2"
}

variable "AWS_ACCESS_KEY_ID_LAMBDA" {}
variable "AWS_SECRET_ACCESS_KEY_LAMBDA" {}
variable "S3_BUCKET" {}

# this identifies that the config runs on AWS
provider "aws" {
  region = var.aws_region
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_func/index.py"
  output_path = "lambda_function.zip"
}

#We need to create a role, a set of policies  and attach the set to the role

# 1. Create role
resource "aws_iam_role" "role" {
  name = "iam_for_geoprocessing_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

# 2. Create Policy
resource "aws_iam_policy" "policy" {
  name = "s3-ec2-policy"
  description = "s3 and ec2 policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Effect": "Allow",
        "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "logs:DescribeLogStreams"
        ],
        "Resource": "arn:aws:logs:*:*:*"
    },
    {
        "Effect": "Allow",
        "Action": [
            "ec2:RunInstances"
        ],
        "Resource": "arn:aws:ec2:*:*:*"
    },
    {
          "Effect": "Allow",
          "Action": ["s3:ListBucket"],
          "Resource": ["arn:aws:s3:::${var.S3_BUCKET}"]
    },
    {
        "Effect": "Allow",
        "Action": "s3:*Object",
        "Resource": [
          "arn:aws:s3:::${var.S3_BUCKET}/*"
        ]
    }
  ]
} 
EOF
}

# 2. Attach Policy to role
resource "aws_iam_role_policy_attachment" "role-policy-attachment" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy.arn
}

# Create lambda function
resource "aws_lambda_function" "process_file" {
  filename         = "lambda_function.zip"
  function_name    = "process_geodb_file"
  role             = aws_iam_role.role.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.7"

  environment {
    variables = {
      AWS_ACCESS_KEY_ID_LAMBDA     = var.AWS_ACCESS_KEY_ID_LAMBDA
      AWS_SECRET_ACCESS_KEY_LAMBDA = var.AWS_SECRET_ACCESS_KEY_LAMBDA
    }
  }
}

# Create bucket
resource "aws_s3_bucket" "bucket" {
  bucket = var.S3_BUCKET
}

# Let the Lambda be kicked off due to a bucket invokation
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_file.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.bucket.arn
}


# Start the lambda if an object that matches <bucket>/input/*.zip is created
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_file.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".zip"
  }

}
