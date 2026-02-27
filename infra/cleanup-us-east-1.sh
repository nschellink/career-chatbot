#!/usr/bin/env bash
# Remove leftover career-chatbot resources in us-east-1.
# Run from infra/: ./cleanup-us-east-1.sh
# Requires: aws CLI, permissions to delete EC2, S3, SSM, IAM, security groups.

set -e
REGION="${AWS_REGION:-us-east-1}"
APP_NAME="career-chatbot"
PREFIX="${APP_NAME}-"

echo "Cleaning up career-chatbot resources in $REGION ..."

# 1. EC2 instances (tag App = career-chatbot)
INSTANCES=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:App,Values=$APP_NAME" "Name=instance-state-name,Values=pending,running,stopped,stopping" \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)
if [[ -n "$INSTANCES" ]]; then
  for id in $INSTANCES; do
    echo "  Terminating instance $id"
    aws ec2 terminate-instances --region "$REGION" --instance-ids "$id" >/dev/null
  done
  echo "  Waiting for instances to terminate..."
  for id in $INSTANCES; do
    aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$id" 2>/dev/null || true
  done
else
  echo "  No EC2 instances found."
fi

# 2. Security groups (tag App = career-chatbot, name prefix career-chatbot-)
SGS=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=tag:App,Values=$APP_NAME" "Name=group-name,Values=${PREFIX}*" \
  --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || true)
if [[ -n "$SGS" ]]; then
  for sg in $SGS; do
    echo "  Deleting security group $sg"
    aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null || echo "    (retry after dependencies are gone)"
  done
  # Retry once in case we had to wait for instances
  for sg in $SGS; do
    aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null || true
  done
else
  echo "  No matching security groups found."
fi

# 3. S3 buckets (prefix career-chatbot-context-) in us-east-1
BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${APP_NAME}-context-')].Name" --output text 2>/dev/null || true)
for bucket in $BUCKETS; do
  BUCKET_REGION=$(aws s3api get-bucket-location --bucket "$bucket" --query 'LocationConstraint' --output text 2>/dev/null || echo "None")
  if [[ "$BUCKET_REGION" == "None" || "$BUCKET_REGION" == "null" || -z "$BUCKET_REGION" ]]; then BUCKET_REGION="us-east-1"; fi
  if [[ "$BUCKET_REGION" != "$REGION" ]]; then echo "  Skipping bucket $bucket (in $BUCKET_REGION, not $REGION)"; continue; fi
  aws s3api list-object-versions --bucket "$bucket" \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
  --output json > /tmp/versions.json

aws s3api list-object-versions --bucket "$bucket" \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
  --output json > /tmp/delete-markers.json

# Delete versions (if any)
if [ "$(jq '.Objects | length' /tmp/versions.json)" -gt 0 ]; then
  aws s3api delete-objects --bucket "$bucket" --delete file:///tmp/versions.json
fi

# Delete delete-markers (if any)
if [ "$(jq '.Objects | length' /tmp/delete-markers.json)" -gt 0 ]; then
  aws s3api delete-objects --bucket "$bucket" --delete file:///tmp/delete-markers.json
fi
  echo "  Emptying and deleting bucket $bucket"
  aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
  aws s3api delete-bucket --bucket "$bucket"
done
if [[ -z "$BUCKETS" ]]; then
  echo "  No matching S3 buckets found."
fi

# 4. SSM parameters under /career-chatbot/
PARAMS=$(aws ssm get-parameters-by-path --region "$REGION" --path "/$APP_NAME/" --recursive --query 'Parameters[].Name' --output text 2>/dev/null || true)
if [[ -n "$PARAMS" ]]; then
  for name in $PARAMS; do
    echo "  Deleting SSM parameter $name"
    aws ssm delete-parameter --region "$REGION" --name "$name"
  done
else
  echo "  No SSM parameters under /$APP_NAME/."
fi

# 5. IAM: instance profiles and roles (name prefix career-chatbot-)
# Instance profiles
PROFILES=$(aws iam list-instance-profiles --query "InstanceProfiles[?starts_with(InstanceProfileName, '${PREFIX}')].InstanceProfileName" --output text 2>/dev/null || true)
for profile in $PROFILES; do
  echo "  Removing role from instance profile $profile"
  ROLE=$(aws iam get-instance-profile --instance-profile-name "$profile" --query 'InstanceProfile.Roles[0].RoleName' --output text 2>/dev/null || true)
  aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$ROLE" 2>/dev/null || true
  echo "  Deleting instance profile $profile"
  aws iam delete-instance-profile --instance-profile-name "$profile"
done

# Roles (with optional prefix; list by tag or by name prefix)
ROLES=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '${PREFIX}')].RoleName" --output text 2>/dev/null || true)
for role in $ROLES; do
  echo "  Deleting inline policies and role $role"
  for policy in $(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text 2>/dev/null); do
    aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
  done
  aws iam delete-role --role-name "$role"
done

echo "Done. us-east-1 cleanup finished."
