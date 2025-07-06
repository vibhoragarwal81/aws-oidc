
provider "aws" {
  region = "us-east-1"
}

data "aws_organizations_organization" "org" {}

data "aws_organizations_accounts" "accounts" {}

resource "null_resource" "create_iam_roles" {
  count = length(data.aws_organizations_accounts.accounts.accounts)

  provisioner "local-exec" {
    command = <<EOT
ACCOUNT_ID=$(echo '${data.aws_organizations_accounts.accounts.accounts[count.index].id}')
ROLE_NAME="GitHubActionsEC2DeployRole"
ORG_ASSUME_ROLE_NAME="GitHubActionsTerraformRole"
GITHUB_REPO="vibhoragarwal81/aws-oidc"

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::$ACCOUNT_ID:role/$ORG_ASSUME_ROLE_NAME \
  --role-session-name GitHubActionsSession \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

AWS_ACCESS_KEY_ID=$(echo $CREDS | cut -d' ' -f1)
AWS_SECRET_ACCESS_KEY=$(echo $CREDS | cut -d' ' -f2)
AWS_SESSION_TOKEN=$(echo $CREDS | cut -d' ' -f3)

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN

if aws iam get-role --role-name $ROLE_NAME >/dev/null 2>&1; then
  echo "Role $ROLE_NAME already exists in $ACCOUNT_ID"
else
  echo "Creating role $ROLE_NAME in $ACCOUNT_ID"

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
          "token.actions.githubusercontent.com:sub": "repo:$GITHUB_REPO:ref:refs/heads/main"
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
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://trust-policy.json

  aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name GitHubActionsPermissions \
    --policy-document file://permissions-policy.json

  rm trust-policy.json permissions-policy.json
fi
EOT
  }
}
