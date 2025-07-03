# aws-oidc
##AWS OIDC repository
### added some test content

```
Step 1: Set Up Your GitHub Repository
🔹 What You’ll Do:
Create a GitHub repo to store your Terraform code.
Enable GitHub Actions for automation.
🔧 Instructions:
Go to GitHub and log in.
Click New Repository.
Name it something like aws-org-iam-automation.
Choose Public.
Check Add a README file.
Click Create repository.
```
## once it is done, check the tools availability on your machine by using 
```
aws --version
terraform --version
code --version
```
## if these are installed skip the next step

```
step 2: Install Required Tools Locally
You’ll need these tools installed on your machine:

Terraform
AWS CLI
Git
use a package manager like chocolatey to install these on your machine
```

## create oidc.tf
```

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "github_oidc_role" {
  name = "GitHubActionsTerraformRole"

  assume_role_policy = <<POLICY

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}

POLICY
}

resource "aws_iam_role_policy" "terraform_permissions" {
  name = "TerraformBasicPermissions"
  role = aws_iam_role.github_oidc_role.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "iam:*",
          "organizations:ListAccounts",
          "sts:AssumeRole",
          "cloudformation:*",
          "s3:*"
        ],
        "Resource": "*"
      }
    ]
  })
}
```

## Replace placeholders in the file:

YOUR_ACCOUNT_ID → Your AWS account ID.
YOUR_GITHUB_ORG → Your GitHub organization or username.
YOUR_REPO → Your GitHub repository name.
Deploy the role:

`Run terraform init`
`Run terraform plan`
`Run terraform apply`
Use this role in GitHub Actions:

Configure GitHub Actions to assume this role using the aws-actions/configure-aws-credentials action.

##  Next create basic GitHub Actions workflow file that uses the IAM role you created with OIDC to authenticate into AWS and run Terraform:

## now clone the repository into local machine if not already done
`git clone https://github.com/YOUR_GITHUB_USERNAME/aws-orgb-iam-automation.git`
`cd aws-orgb-iam-automation`


## Create the Workflow Directory
`mkdir -p .github/workflows`

Create a workflow file in this folder
`nano .github/workflows/deploy-iam-role.yml`

## paste below content in the file and save
```
name: Deploy IAM Role to AWS

on:
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Configure AWS credentials using OIDC
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::<YOUR_ACCOUNT_ID>:role/GitHubActionsTerraformRole
          aws-region: us-east-1

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v2

      - name: Terraform Init
        run: terraform init

      - name: Terraform Plan
        run: terraform plan

      - name: Terraform Apply
        run: terraform apply -auto-approve
```

## create a main.tf file for terraform to apply configuration

`nano main.tf'  
## paste below code and save

```
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "example" {
  bucket = "example-terraform-bucket-${random_id.suffix.hex}"
  force_destroy = true
}

resource "random_id" "suffix" {
  byte_length = 4
}
```


commit and check push changes

```
git add .
git commit -m "Add GitHub Actions workflow and main.tf for IAM role deployment"
git push origin main
```

## Now watch the workflow

Watch the Workflow
Go to the Actions tab in GitHub and watch the workflow run again. It should now:

Initialize Terraform
Plan the S3 bucket creation
Apply it to your AWS account




