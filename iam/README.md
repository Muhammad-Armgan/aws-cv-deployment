# IAM Configuration

## Overview

Two IAM roles provide temporary, automatically rotated credentials to EC2 and Lambda.
No long-term access keys are stored anywhere — not in user data, not in environment
variables, not in the repository.

---

## EC2 Role — `cv-ec2-role-23l-3076`

**Trusted service:** `ec2.amazonaws.com`

### Trust policy (`ec2-trust-policy.json`)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Inline permission policy — `cv-ec2-s3-read` (`ec2-permission-policy.json`)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GetSiteObjects",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::cv-23l-3076/site/*"
    },
    {
      "Sid": "ListSitePrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::cv-23l-3076",
      "Condition": {
        "StringLike": { "s3:prefix": "site/*" }
      }
    }
  ]
}
```

No wildcards in actions or resources. `s3:DeleteObject`, `s3:PutObject`, and all
other write actions are not granted — attempts return `AccessDenied`.

---

## Lambda Role — `cv-lambda-role-23l-3076`

**Trusted service:** `lambda.amazonaws.com`

### Trust policy (`lambda-trust-policy.json`)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Attached managed policy

`arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole`

This is the only wildcard exception allowed — it grants CloudWatch Logs write
access using AWS-managed statements.

### Inline permission policy — `cv-lambda-s3-read` (`lambda-permission-policy.json`)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GetSiteObjects",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::cv-23l-3076/site/*"
    }
  ]
}
```

No `s3:ListBucket` — the Lambda handler uses exact keys, so listing is unnecessary.
No wildcards in actions or resources.

---

## Security Notes

- Both roles restrict access to the `site/` prefix of `cv-23l-3076` only.
- Neither role can write to, delete from, or list the full bucket.
- No access keys are committed to the repository or embedded in any script.
