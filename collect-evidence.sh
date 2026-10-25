#!/usr/bin/env bash
# collect-evidence.sh
# Usage: ./collect-evidence.sh BUCKET EC2_ADDRESS LAMBDA_URL
set -u

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 BUCKET EC2_ADDRESS LAMBDA_URL"
  exit 1
fi

BUCKET="$1"
EC2_ADDRESS="$2"
LAMBDA_URL="$3"
OUT="evidence.txt"
REGION="ap-southeast-2"
EC2_NAME="cv-ec2-23l-3076"
EC2_ROLE="cv-ec2-role-23l-3076"
LAMBDA_NAME="cv-func-23l-3076"
LAMBDA_ROLE="cv-lambda-role-23l-3076"
SG_NAME="cv-ec2-sg-23l-3076"

# ── dependency checks ─────────────────────────────────────────────────────────
command -v aws  >/dev/null 2>&1 || { echo "ERROR: AWS CLI not found."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found.";    exit 1; }

# ── helper ────────────────────────────────────────────────────────────────────
section() {
  local title="$1"; shift
  {
    printf '\n== %s ==\n' "$title"
    "$@" 2>&1 || printf 'NOTE: command failed — check permissions or resource names.\n'
  } >> "$OUT"
}

# ── header ────────────────────────────────────────────────────────────────────
{
  printf 'CV AWS Assignment — Evidence\n'
  printf 'Collected : %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  printf 'Region    : %s\n' "$REGION"
  printf 'Bucket    : %s\n' "$BUCKET"
  printf 'EC2       : %s\n' "$EC2_ADDRESS"
  printf 'Lambda    : %s\n' "$LAMBDA_URL"
} > "$OUT"

# ── sections ──────────────────────────────────────────────────────────────────

section "caller" \
  aws sts get-caller-identity

section "public-access" \
  aws s3api get-public-access-block \
    --bucket "$BUCKET" \
    --region "$REGION"

section "versioning" \
  aws s3api get-bucket-versioning \
    --bucket "$BUCKET" \
    --region "$REGION"

section "objects" \
  aws s3 ls "s3://$BUCKET/site/" --region "$REGION"

section "ec2-policy" \
  aws iam get-role-policy \
    --role-name "$EC2_ROLE" \
    --policy-name cv-ec2-s3-read

section "lambda-policy" bash -c '
  echo "--- Attached managed policies ---"
  aws iam list-attached-role-policies \
    --role-name "'"$LAMBDA_ROLE"'" \
    --region "'"$REGION"'" 2>&1
  echo ""
  echo "--- Inline policy ---"
  aws iam get-role-policy \
    --role-name "'"$LAMBDA_ROLE"'" \
    --policy-name cv-lambda-s3-read 2>&1
'

section "security-group" \
  aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=group-name,Values=$SG_NAME" \
    --output json

section "instance" \
  aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=$EC2_NAME" \
    --query "Reservations[].Instances[].{
               ID:InstanceId,
               State:State.Name,
               Type:InstanceType,
               PublicIP:PublicIpAddress,
               IMDSv2:MetadataOptions.HttpTokens,
               IAMProfile:IamInstanceProfile.Arn
             }" \
    --output json

section "endpoints" bash -c '
  check_url() {
    local label="$1" url="$2"
    printf "\nURL : %s\n" "$url"
    curl -sSL -o /dev/null \
      -w "Status       : %{http_code}\nContent-Type : %{content_type}\n" \
      --max-time 20 "$url" \
    || printf "NOTE: request failed.\n"
  }
  check_url "EC2 root"       "http://'"$EC2_ADDRESS"'/"
  check_url "EC2 style.css"  "http://'"$EC2_ADDRESS"'/style.css"
  check_url "EC2 cv.pdf"     "http://'"$EC2_ADDRESS"'/cv.pdf"
  check_url "Lambda root"    "'"${LAMBDA_URL%/}"'/"
  check_url "Lambda 404"     "'"${LAMBDA_URL%/}"'/nonexistent"
  check_url "S3 direct"      "https://'"$BUCKET"'.s3.'"$REGION"'.amazonaws.com/site/index.html"
'

section "lambda-logs" \
  aws logs tail "/aws/lambda/$LAMBDA_NAME" \
    --since 1d \
    --region "$REGION"

section "log-retention" \
  aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/$LAMBDA_NAME" \
    --region "$REGION" \
    --query 'logGroups[].{LogGroup:logGroupName,RetentionInDays:retentionInDays}' \
    --output json

printf '\nDONE\n'
