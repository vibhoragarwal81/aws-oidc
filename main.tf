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

data "aws_caller_identity" "current" {}

resource "null_resource" "create_roles" {
  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

MGMT_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ORG_ACCOUNTS=$(aws organizations list-accounts --query "Accounts[?Status=='ACTIVE'].Id" --output text)

for ACCOUNT_ID in $ORG_ACCOUNTS; do
  echo "Processing account: $ACCOUNT_ID"

  CREDS=$(aws sts assume-role \
    --role-arn arn:aws:iam::$ACCOUNT_ID:role/GitHubActionsOrgAdminRole \
    --role-session-name SetupSession \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text 2>/dev/null || true)

  if [ -z "$CREDS" ]; then
    echo "OrgAccountAdminRole not found in $ACCOUNT_ID. Creating it..."

    CREDS_MGMT=$(aws sts assume-role \
      --role-arn arn:aws:iam::$MGMT_ACCOUNT_ID:role/GitHubActionsOrgAdminRole \
      --role-session-name MgmtSession \
      --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
      --output text)

    export AWS_ACCESS_KEY_ID=$(echo $CREDS_MGMT | cut -d' ' -f1)
    export AWS_SECRET_ACCESS_KEY=$(echo $CREDS_MGMT | cut -d' ' -f2)
    export AWS_SESSION_TOKEN=$(echo $CREDS_MGMT | cut -d' ' -f3)

    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::$MGMT_ACCOUNT_ID:root"
    },
    "Action": "sts:AssumeRole"
  }]
}
EOF
)

    aws sts assume-role \
      --role-arn arn:aws:iam::$MGMT_ACCOUNT_ID:role/GitHubActionsOrgAdminRole \
      --role-session-name MgmtSession > /dev/null

    CREDS_TARGET=$(aws sts assume-role \
      --role-arn arn:aws:iam::$MGMT_ACCOUNT_ID:role/GitHubActionsOrgAdminRole \
      --role-session-name MgmtSession \
      --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
      --output text)

    export AWS_ACCESS_KEY_ID=$(echo $CREDS_TARGET | cut -d' ' -f1)
    export AWS_SECRET_ACCESS_KEY=$(echo $CREDS_TARGET | cut -d' ' -f2)
    export AWS_SESSION_TOKEN=$(echo $CREDS_TARGET | cut -d' ' -f3)

    aws iam create-role \
      --role-name OrgAccountAdminRole \
      --assume-role-policy-document "$TRUST_POLICY" \
      --output text || true

    aws iam attach-role-policy \
      --role-name OrgAccountAdminRole \
      --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
  fi

  CREDS=$(aws sts assume-role \
    --role-arn arn:aws:iam::$ACCOUNT_ID:role/OrgAccountAdminRole \
    --role-session-name SetupSession \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)

  export AWS_ACCESS_KEY_ID=$(echo $CREDS | cut -d' ' -f1)
  export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | cut -d' ' -f2)
  export AWS_SESSION_TOKEN=$(echo $CREDS | cut -d' ' -f3)

  if aws iam get-role --role-name GitHubActionsEC2DeployRole >/dev/null 2>&1; then
    echo "GitHubActionsEC2DeployRole already exists in $ACCOUNT_ID"
  else
    echo "Creating GitHubActionsEC2DeployRole in $ACCOUNT_ID"

    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:ref:refs/heads/main"
      }
    }
  }]
}
EOF
)

    PERMISSIONS_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:DescribeInstances",
      "s3:ListBucket"
    ],
    "Resource": "*"
  }]
}
EOF
)

    aws iam create-role \
      --role-name GitHubActionsEC2DeployRole \
      --assume-role-policy-document "$TRUST_POLICY"

    aws iam put-role-policy \
      --role-name GitHubActionsEC2DeployRole \
      --policy-name GitHubActionsPermissions \
      --policy-document "$PERMISSIONS_POLICY"
  fi
done
EOT
  }
}