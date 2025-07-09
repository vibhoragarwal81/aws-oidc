#!/bin/bash

# === CONFIGURATION FROM ENV ===
TOKEN_FILE="token.jwt"
CREDENTIALS_FILE="aws_temp_creds.sh"

# === STEP 1: Get OIDC Token from Entra ID ===
echo "🔐 Requesting token from Entra ID..."
TOKEN_RESPONSE=$(curl -s -X POST "https://login.microsoftonline.com/ac877863-5f25-4759-8c09-4d7b336b9341/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=e331bd64-25f4-4c4b-a58a-6a92a9ff94d7" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "scope=api://aws-oidc/.default")

OIDC_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ "$OIDC_TOKEN" == "null" ] || [ -z "$OIDC_TOKEN" ]; then
  echo "❌ Failed to retrieve token. Response:"
  echo "$TOKEN_RESPONSE"
  exit 1
fi

echo "$OIDC_TOKEN" > $TOKEN_FILE
echo "✅ Token saved to $TOKEN_FILE"

# === STEP 2: Assume Role in AWS ===
echo "🔄 Assuming role in AWS account $MANAGEMENT_ACCOUNT_ID..."
ASSUME_ROLE_OUTPUT=$(aws sts assume-role-with-web-identity \
  --role-arn arn:aws:iam::872515281040:role/aws-oidc-role \
  --role-session-name EntraOIDCSession \
  --web-identity-token file://$TOKEN_FILE \
  --duration-seconds 3600)

if [ $? -ne 0 ]; then
  echo "❌ Failed to assume role."
  exit 1
fi

# === STEP 3: Export Temporary Credentials ===
ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
SECRET_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

cat > $CREDENTIALS_FILE <<EOF
export AWS_ACCESS_KEY_ID=$ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SECRET_KEY
export AWS_SESSION_TOKEN=$SESSION_TOKEN
EOF

echo "✅ Temporary credentials saved to $CREDENTIALS_FILE"
