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

data "aws_organizations_organization" "org" {}

data "aws_organizations_accounts" "accounts" {}

resource "null_resource" "create_roles" {
  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

TARGET_ROLE_NAME="GitHubActionsEC2DeployRole"
ADMIN_ROLE_NAME="OrgAccountAdminRole"
GITHUB_REPO="vibhoragarwal81/aws-oidc"
REGION="us-east-1"

ACCOUNT_IDS=$(aws organizations list-accounts --query "Accounts[?Status=='ACTIVE'].Id" --output text)

for ACCOUNT_ID in $ACCOUNT_IDS; do
  echo "Processing account: $ACCOUNT_ID"

  # Assume OrgAccountAdminRole if it exists
  CREDS=$(aws sts assume-role     --role-arn arn:aws:iam::$ACCOUNT_ID:role/$ADMIN_ROLE_NAME     --role-session-name GitHubActionsSession     --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]'     --output text 2>/dev/null || true)

  if [ -z "$CREDS" ]; then
    echo "Creating $ADMIN_ROLE_NAME in $ACCOUNT_ID"

    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/GitHubActionsTerraformRole"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

    aws iam create-role       --role-name $ADMIN_ROLE_NAME       --assume-role-policy-document "$TRUST_POLICY"       --region $REGION       --profile default       --output json

    aws iam attach-role-policy       --role-name $ADMIN_ROLE_NAME       --policy-arn arn:aws:iam::aws:policy/AdministratorAccess       --region $REGION       --profile default
  fi

  # Re-attempt to assume OrgAccountAdminRole
  CREDS=$(aws sts assume-role     --role-arn arn:aws:iam::$ACCOUNT_ID:role/$ADMIN_ROLE_NAME     --role-session-name GitHubActionsSession     --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]'     --output text)

  export AWS_ACCESS_KEY_ID=$(echo $CREDS | cut -d' ' -f1)
  export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | cut -d' ' -f2)
  export AWS_SESSION_TOKEN=$(echo $CREDS | cut -d' ' -f3)

  if aws iam get-role --role-name $TARGET_ROLE_NAME >/dev/null 2>&1; then
    echo "✅ $TARGET_ROLE_NAME already exists in $ACCOUNT_ID"
  else
    echo "🚀 Creating $TARGET_ROLE_NAME in $ACCOUNT_ID"

    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO}:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF
)

    PERMISSIONS_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "s3:ListBucket"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

    aws iam create-role       --role-name $TARGET_ROLE_NAME       --assume-role-policy-document "$TRUST_POLICY"

    aws iam put-role-policy       --role-name $TARGET_ROLE_NAME       --policy-name GitHubActionsPermissions       --policy-document "$PERMISSIONS_POLICY"
  fi
done
EOT
  }
}