
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

resource "null_resource" "create_roles" {
  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

# List all active AWS Organization accounts
ACCOUNT_IDS=$(aws organizations list-accounts --query "Accounts[?Status=='ACTIVE'].Id" --output text)

for ACCOUNT_ID in $ACCOUNT_IDS; do
  echo "Processing account: $ACCOUNT_ID"

  CREDS=$(aws sts assume-role \
    --role-arn arn:aws:iam::$ACCOUNT_ID:role/OrgAccountAdminRole \
    --role-session-name GitHubActionsSession \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)

  export AWS_ACCESS_KEY_ID=$(echo $CREDS | cut -d' ' -f1)
  export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | cut -d' ' -f2)
  export AWS_SESSION_TOKEN=$(echo $CREDS | cut -d' ' -f3)

  # Check if GitHubActionsEC2DeployRole exists
  if aws iam get-role --role-name GitHubActionsEC2DeployRole >/dev/null 2>&1; then
    echo "✅ Role GitHubActionsEC2DeployRole already exists in $ACCOUNT_ID"
  else
    echo "🚀 Creating role GitHubActionsEC2DeployRole in $ACCOUNT_ID"

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
          "token.actions.githubusercontent.com:sub": "vibhoragarwal81/aws-oidc:ref:refs/heads/main"
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

    echo "$TRUST_POLICY" > trust-policy.json
    echo "$PERMISSIONS_POLICY" > permissions-policy.json

    aws iam create-role \
      --role-name GitHubActionsEC2DeployRole \
      --assume-role-policy-document file://trust-policy.json

    aws iam put-role-policy \
      --role-name GitHubActionsEC2DeployRole \
      --policy-name GitHubActionsPermissions \
      --policy-document file://permissions-policy.json

    rm trust-policy.json permissions-policy.json

    echo "✅ Role created in $ACCOUNT_ID"
  fi
done
EOT
  }
}
