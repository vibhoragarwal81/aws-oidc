#!/bin/bash

ROLE_NAME="OrganizationAccountAccessRole"
SESSION_NAME="ListIAMUsersSession"
OUTPUT_FILE="iam_users_by_account.json"

echo "{" > $OUTPUT_FILE

# Step 1: List all AWS accounts
ACCOUNT_IDS=$(aws organizations list-accounts --query "Accounts[?Status=='ACTIVE'].Id" --output text)

# Step 2: Loop through each account
for ACCOUNT_ID in $ACCOUNT_IDS; do
  echo -e "\n🔄 Assuming role in account: $ACCOUNT_ID"

  CREDS=$(aws sts assume-role \
    --role-arn arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME \
    --role-session-name $SESSION_NAME \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)

  if [ $? -ne 0 ]; then
    echo "❌ Failed to assume role in account $ACCOUNT_ID"
    continue
  fi

  ACCESS_KEY=$(echo $CREDS | awk '{print $1}')
  SECRET_KEY=$(echo $CREDS | awk '{print $2}')
  SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')

  USERS=$(AWS_ACCESS_KEY_ID=$ACCESS_KEY \
          AWS_SECRET_ACCESS_KEY=$SECRET_KEY \
          AWS_SESSION_TOKEN=$SESSION_TOKEN \
          aws iam list-users --query 'Users[*].UserName' --output json)

  echo "📋 IAM Users in account $ACCOUNT_ID:"
  echo "$USERS" | jq -r '.[] | " - \(. )"'

  echo "  \"$ACCOUNT_ID\": $USERS," >> $OUTPUT_FILE
done

# Remove trailing comma and close JSON object
sed -i '' -e '$ s/,$//' $OUTPUT_FILE 2>/dev/null || sed -i '$ s/,$//' $OUTPUT_FILE
echo "}" >> $OUTPUT_FILE

echo -e "\n✅ Output saved to $OUTPUT_FILE"
