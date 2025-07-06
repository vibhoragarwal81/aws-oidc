
resource "null_resource" "create_roles" {
  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

MGMT_ACCOUNT_ID="872515281040"
GITHUB_REPO="vibhoragarwal81/aws-oidc"
AWS_REGION="us-east-1"
ORG_ASSUME_ROLE_NAME="OrgAccountAdminRole"
TARGET_ROLE_NAME="GitHubActionsEC2DeployRole"

echo "Fetching AWS Organization accounts..."
ACCOUNT_IDS=$(aws organizations list-accounts --query "Accounts[?Status=='ACTIVE'].Id" --output text)

for ACCOUNT_ID in $ACCOUNT_IDS; do
  if [ "$ACCOUNT_ID" == "$MGMT_ACCOUNT_ID" ]; then
    echo "Skipping management account $ACCOUNT_ID"
    continue
  fi

  echo "Creating OrgAccountAdminRole in $ACCOUNT_ID if not present..."
  CREDS=$(aws sts assume-role     --role-arn arn:aws:iam::$ACCOUNT_ID:role/$ORG_ASSUME_ROLE_NAME     --role-session-name BootstrapSession     --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]'     --output text 2>/dev/null || true)

  if [ -z "$CREDS" ]; then
    echo "Attempting to create OrgAccountAdminRole in $ACCOUNT_ID"

    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$MGMT_ACCOUNT_ID:role/GitHubActionsTerraformRole"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

    CREDS_MGMT=$(aws sts assume-role       --role-arn arn:aws:iam::$MGMT_ACCOUNT_ID:role/GitHubActionsTerraformRole       --role-session-name MgmtSession       --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]'       --output text)

    export AWS_ACCESS_KEY_ID=$(echo $CREDS_MGMT | cut -d' ' -f1)
    export AWS_SECRET_ACCESS_KEY=$(echo $CREDS_MGMT | cut -d' ' -f2)
    export AWS_SESSION_TOKEN=$(echo $CREDS_MGMT | cut -d' ' -f3)

    aws iam create-role       --role-name $ORG_ASSUME_ROLE_NAME       --assume-role-policy-document "$TRUST_POLICY"       --output text --region $AWS_REGION --profile default 2>/dev/null || echo "OrgAccountAdminRole may already exist"

    aws iam attach-role-policy       --role-name $ORG_ASSUME_ROLE_NAME       --policy-arn arn:aws:iam::aws:policy/AdministratorAccess       --region $AWS_REGION --profile default || true

    echo "Waiting for role propagation..."
    sleep 10

    CREDS=$(aws sts assume-role       --role-arn arn:aws:iam::$ACCOUNT_ID:role/$ORG_ASSUME_ROLE_NAME       --role-session-name BootstrapSession       --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]'       --output text 2>/dev/null || true)
  fi

  if [ -z "$CREDS" ]; then
    echo "❌ Failed to assume OrgAccountAdminRole in $ACCOUNT_ID"
    continue
  fi

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
          "token.actions.githubusercontent.com:sub": "repo:vibhoragarwal81/aws-oidc"
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

    aws iam create-role       --role-name $TARGET_ROLE_NAME       --assume-role-policy-document "$TRUST_POLICY" || echo "Failed to create $TARGET_ROLE_NAME"

    aws iam put-role-policy       --role-name $TARGET_ROLE_NAME       --policy-name GitHubActionsPermissions       --policy-document "$PERMISSIONS_POLICY" || echo "Failed to attach policy to $TARGET_ROLE_NAME"
  fi
done
EOT
  }
}
