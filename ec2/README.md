# EC2 Configuration

## Instance Details

| Field               | Value                         |
|---------------------|-------------------------------|
| Instance name       | `cv-ec2-23l-3076`             |
| Region              | `ap-southeast-2` (Sydney)     |
| Instance type       | `t3.micro` (free-tier eligible)|
| Operating system    | Amazon Linux 2023             |
| Web server          | Apache HTTP Server (`httpd`)  |
| IAM role            | `cv-ec2-role-23l-3076`        |
| IMDSv2              | Required (`HttpTokens: required`) |

## Security Group (`cv-ec2-sg-23l-3076`)

| Direction | Protocol | Port | Source          |
|-----------|----------|------|-----------------|
| Inbound   | TCP      | 80   | `0.0.0.0/0`     |
| Inbound   | TCP      | 22   | `<your-ip>/32` or closed |
| Outbound  | All      | All  | `0.0.0.0/0`     |

Port 22 is either restricted to your own IP (`/32`) or has no inbound rule at all.
No other inbound rules exist.

## Tags

| Key    | Value       |
|--------|-------------|
| Owner  | `23L-3076`  |
| Course | `cloud`     |

## Website Synchronization

The `sync-cv.sh` script is triggered by a **systemd timer** every **5 minutes**.

It:
1. Runs `aws s3 sync s3://cv-23l-3076/site/ /var/www/html/` using the EC2 IAM role (no access keys).
2. Reads the instance ID from the metadata service using a signed IMDSv2 token.
3. Replaces `{{HOSTED_ON}}` in `/var/www/html/index.html` with `EC2 <instance-id>`.
4. Appends a timestamped result line to `/var/log/cv-sync.log`.

## Files in this folder

| File          | Purpose                                      |
|---------------|----------------------------------------------|
| `user-data.sh`| Installs Apache, deploys the systemd timer, runs first sync |
| `sync-cv.sh`  | Syncs S3 → web root, replaces placeholder, logs result |
