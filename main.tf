
resource "null_resource" "create_roles" {
  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

MANAGEMENT_ACCOUNT_ID="872515281040"
TARGET_ROLE_NAME="GitHubActionsEC2DeployRole"
ORG_ASSUME_ROLE_NAME="OrgAccountAdminRole"
AWS_REGION="us-east-1"
GITHUB_REPO="vibhoragarwal81/aws-oidc"

ACCOUNT_IDS=$(aws organizations list-accounts --query "Accounts[?Status=='ACTIVE'].Id" --output text)

for ACCOUNT_ID in $ACCOUNT_IDS; do
  if [ "$ACCOUNT_ID" == "$MANAGEMENT_ACCOUNT_ID" ]; then
    echo "Skipping management account: $ACCOUNT_ID"
    continue
  fi

  echo "Processing account: $ACCOUNT_ID"

  CREDS=$(aws sts assume-role     --role-arn arn:aws:iam::$ACCOUNT_ID:role/$ORG_ASSUME_ROLE_NAME     --role-session-name GitHubActionsSession     --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]'     --output text 2>/dev/null || true)

  if [ -z "$CREDS" ]; then
    echo "❌ Failed to assume role in $ACCOUNT_ID"
    continue
  fi

  export AWS_ACCESS_KEY_ID=$(echo $CREDS | cut -d' ' -f1)
  export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | cut -d' ' -f2)
  export AWS_SESSION_TOKEN=$(echo $CREDS | cut -d' ' -f3)

  if aws iam get-role --role-name $TARGET_ROLE_NAME >/dev/null 2>&1; then
    echo "✅ Role $TARGET_ROLE_NAME already exists in $ACCOUNT_ID"
    continue
  fi

  echo "🚀 Creating role $TARGET_ROLE_NAME in $ACCOUNT_ID"

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

  echo "$TRUST_POLICY" > trust-policy.json
  echo "$PERMISSIONS_POLICY" > permissions-policy.json

  aws iam create-role     --role-name $TARGET_ROLE_NAME     --assume-role-policy-document file://trust-policy.json || true

  aws iam put-role-policy     --role-name $TARGET_ROLE_NAME     --policy-name GitHubActionsPermissions     --policy-document file://permissions-policy.json || true

  rm -f trust-policy.json permissions-policy.json

  echo "✅ Role created in $ACCOUNT_ID"
done
EOT
  }
}
