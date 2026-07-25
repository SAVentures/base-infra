# CloudFront policies and functions are account-level reusable resources, and
# were byte-identical across both products. Defined once here; products
# reference them by id. This also removes the name-collision class that made
# products/protoapp impossible to clone.

resource "aws_cloudfront_function" "spa_routing" {
  name    = "shared-spa-routing"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite non-asset, non-API requests to index.html for SPA routing"
  publish = true
  code    = <<-EOT
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // Don't rewrite API requests
    if (uri.startsWith('/api/')) {
        return request;
    }

    // Static assets (anything with an extension) pass through untouched
    if (uri.includes('.')) {
        return request;
    }

    // Client-side routes rewrite to index.html; the browser URL is unchanged
    request.uri = '/index.html';

    return request;
}
EOT
}

resource "aws_cloudfront_cache_policy" "api_no_cache" {
  name        = "shared-api-no-cache"
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

resource "aws_cloudfront_origin_request_policy" "api_origin_request" {
  name    = "shared-api-origin-request"
  comment = "Forward viewer headers, cookies and query strings to the API origin"

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
