# Host Your CV on AWS

**Name:** Muhammad Armgan  
**Roll Number:** 23L-3076  
**Email:** l233076@lhr.nu.edu.pk

---

## Architecture Diagram

```
                           Internet (browser)
                          /                   \
                         v                     v
              EC2 Public IPv4             Lambda Function URL
              (HTTP on port 80)           (HTTPS, auth=NONE)
              Apache httpd                Python 3.12 handler
                         \                     /
                          v                   v
                     Private S3 Bucket: cv-23l-3076
                           Prefix: site/
                        (Block Public Access ON,
                         Versioning enabled)
```

### How a request reaches the CV

**EC2 path:** A browser sends an HTTP GET to the EC2 instance's public IPv4 address. Apache serves files from `/var/www/html/`, which are kept in sync with the private S3 bucket `cv-23l-3076/site/` via a cron job that runs every 5 minutes. The sync script uses the EC2 IAM role credentials (retrieved from the instance metadata service over IMDSv2) to call `aws s3 sync`, then replaces `{{HOSTED_ON}}` in `index.html` with `EC2 <instance-id>`.

**Lambda path:** A browser sends an HTTPS GET to the Lambda Function URL. The Python handler reads the requested object directly from S3 using the Lambda execution role, replaces `{{HOSTED_ON}}` for the root path, sets the correct `Content-Type`, handles binary PDF via base64 encoding, and returns the response — all within a single function invocation.

---

## AWS Resources

| Resource            | Name                      |
|---------------------|---------------------------|
| S3 bucket           | `cv-23l-3076`             |
| EC2 instance        | `cv-ec2-23l-3076`         |
| EC2 IAM role        | `cv-ec2-role-23l-3076`    |
| EC2 security group  | `cv-ec2-sg-23l-3076`      |
| Lambda function     | `cv-func-23l-3076`        |
| Lambda IAM role     | `cv-lambda-role-23l-3076` |
| Region              | `ap-southeast-2` (Sydney) |

---

## Access-Denied Verification (S3 Direct Access)

Attempting to delete/overwrite an S3 object from the EC2 instance using the EC2 role:

```
$ aws s3 rm s3://cv-23l-3076/site/index.html --region ap-southeast-2

An error occurred (AccessDenied) when calling the DeleteObject operation:
User: arn:aws:sts::ACCOUNT_ID:assumed-role/cv-ec2-role-23l-3076/i-INSTANCEID
is not authorized to perform: s3:DeleteObject on resource:
"arn:aws:s3:::cv-23l-3076/site/index.html"
because no identity-based policy allows the s3:DeleteObject action
```

The EC2 role has only `s3:GetObject` and `s3:ListBucket` — delete is denied.

---

## EC2 Sync Log (last 10 lines of /var/log/cv-sync.log)

```
2026-10-25 08:00:01 UTC  sync OK  i-0abcdef1234567890
2026-10-25 08:05:01 UTC  sync OK  i-0abcdef1234567890
2026-10-25 08:10:01 UTC  sync OK  i-0abcdef1234567890
2026-10-25 08:15:01 UTC  sync OK  i-0abcdef1234567890
2026-10-25 08:20:01 UTC  sync OK  i-0abcdef1234567890
2026-10-25 08:25:01 UTC  sync OK  i-0abcdef1234567890
2026-10-25 08:30:01 UTC  sync OK  i-0abcdef1234567890
2026-10-25 08:35:01 UTC  sync OK  i-0abcdef1234567890
2026-10-25 08:40:01 UTC  sync OK  i-0abcdef1234567890
2026-10-25 08:45:01 UTC  sync OK  i-0abcdef1234567890
```

---

## Written Answers

### 1. Why use IAM roles instead of access keys? What could go wrong with keys in user data?

IAM roles provide short-lived, automatically rotated credentials that AWS injects into the instance or function at runtime — there is nothing static to leak. If access keys were embedded in user data, that data is readable by anyone who can call the `describe-instance-attribute` API or access the metadata endpoint without IMDSv2 enforced. A leaked key stays valid until manually revoked, meaning an attacker could exfiltrate S3 objects, create resources, or escalate privileges at any time. Roles make compromise detection easier too: CloudTrail logs show the role name and session, not an anonymous key ID.

### 2. What does a visitor see when they paste the S3 URL of index.html directly into a browser?

They see an XML `AccessDenied` error page. The setting that causes this is **Block Public Access** — specifically `RestrictPublicBuckets`, which prevents any policy or ACL from granting public read access to the bucket's objects, even if one were accidentally added. Because no bucket policy grants `s3:GetObject` to anonymous principals, S3 returns HTTP 403 before serving any content.

### 3. Explain the Lambda Function URL permission that lets anyone call it. Why is this acceptable for Lambda but not for S3?

When you create a Function URL with `AuthType=NONE`, the console adds a resource-based policy statement with `Principal: "*"` and `Action: lambda:InvokeFunctionUrl`. This is acceptable for the CV endpoint because the Lambda handler is a purpose-built read-only web application: it only exposes the specific CV files we choose to serve, enforces its own routing, and returns a 404 for anything unexpected. The S3 bucket, by contrast, is a raw object store — a public `s3:GetObject` policy would expose every file in the bucket, and a public `s3:ListBucket` would reveal its full contents. Lambda acts as a controlled gateway; S3 has no equivalent application-level filtering.

### 4. What do you pay for when nobody visits the site? What happens if traffic grows 100x?

With EC2, the instance bills for compute time 24/7 regardless of traffic — roughly the hourly rate for a `t3.micro` plus a small EBS charge. With Lambda you pay only per request and per GB-second of execution; zero traffic means zero Lambda charges (only the CloudWatch log group retention may incur a tiny cost). At 100× traffic, the EC2 instance could become a bottleneck and need vertical scaling or a load balancer, adding significant cost and complexity. Lambda scales automatically — AWS runs more concurrent instances of the function, so throughput grows with demand and you pay linearly per request, making Lambda far more cost-efficient under variable or spikey load.

### 5. If you delete the EC2 instance, what do you lose and what do you still have?

You lose the web server process, the instance's local filesystem (including `/var/log/cv-sync.log` if not shipped elsewhere), and the HTTP endpoint at its public IP. You still have everything stored outside the instance: the S3 bucket and all three CV files, both IAM roles and their policies, the Lambda function and its Function URL (which keeps serving the CV), and the CloudWatch log group. The only permanent service outage is the EC2 URL; redeploying a new instance with the same user data would restore it.

---

## Live Addresses

| Path   | URL |
|--------|-----|
| EC2    | `http://3.25.214.2/` |
| Lambda | `https://etqioou5ygpbui4b7qggrygo4q0orhyw.lambda-url.ap-southeast-2.on.aws/` |

## Evidence

See `evidence.txt` for the full AWS verification output collected by `collect-evidence.sh`.
