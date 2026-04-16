resource "aws_s3_bucket" "webapp_bucket" {
  bucket = "${var.domain_name}-webapp"

  tags = {
    Name        = "Webapp Static Hosting"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "webapp_bucket_public_access" {
  bucket = aws_s3_bucket.webapp_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "webapp_bucket_policy" {
  bucket = aws_s3_bucket.webapp_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.webapp_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.webapp_distribution.arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudfront_origin_access_control" "webapp_oac" {
  name                              = "webapp-oac"
  description                       = "Origin Access Control for Webapp S3 Bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "spa_routing" {
  name    = "spa-routing-function"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite requests to index.html for SPA routing"
  publish = true
  code    = <<-EOT
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // Don't rewrite API requests
    if (uri.startsWith('/api/')) {
        return request;
    }

    // Check if the URI has a file extension (e.g., .js, .css, .png, .svg)
    // If it does, it's a static asset, so don't rewrite
    if (uri.includes('.')) {
        return request;
    }

    // For all other requests (client-side routes), rewrite to index.html
    // The URL in the browser stays unchanged, allowing TanStack Router to handle routing
    request.uri = '/index.html';

    return request;
}
EOT
}

resource "aws_cloudfront_distribution" "webapp_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = [var.domain_name, "www.${var.domain_name}"]

  origin {
    domain_name              = aws_s3_bucket.webapp_bucket.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.webapp_bucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.webapp_oac.id
  }

  origin {
    domain_name = data.terraform_remote_state.platform.outputs.alb_dns_name
    origin_id   = "ALB-API"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.webapp_bucket.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_routing.arn
    }
  }

  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-API"

    cache_policy_id          = aws_cloudfront_cache_policy.api_cache_policy.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api_origin_request_policy.id

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.ssl_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name        = "Webapp CloudFront Distribution"
    Environment = var.environment
  }
}

resource "aws_cloudfront_cache_policy" "api_cache_policy" {
  name        = "api-no-cache-policy"
  comment     = "No caching for API requests"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_origin_request_policy" "api_origin_request_policy" {
  name    = "api-origin-request-policy"
  comment = "Forward headers needed for API including viewer address, geo, and device info"

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "allViewerAndWhitelistCloudFront"
    headers {
      items = [
        "CloudFront-Viewer-Address",
        "CloudFront-Viewer-Country",
        "CloudFront-Viewer-Country-Region",
        "CloudFront-Viewer-City",
        "CloudFront-Viewer-Postal-Code",
        "CloudFront-Viewer-Metro-Code",
        "CloudFront-Viewer-Time-Zone",
        "CloudFront-Viewer-Latitude",
        "CloudFront-Viewer-Longitude",
        "CloudFront-Is-Mobile-Viewer",
      ]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

resource "aws_cloudwatch_log_group" "cloudfront_logs" {
  name              = "/aws/cloudfront/webapp"
  retention_in_days = 7

  tags = {
    Name        = "CloudFront Webapp Logs"
    Environment = var.environment
  }
}
