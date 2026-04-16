# WEBAPP NOW SERVED VIA S3 + CLOUDFRONT
# See s3-cloudfront.tf for the new webapp hosting configuration
#
# The webapp is now a static Vite app served from S3 through CloudFront
# Environment variables are baked into the build at build time:
# - VITE_GOOGLE_CLIENT_ID
# - VITE_GOOGLE_REDIRECT_URI
# - VITE_STRIPE_PUBLISHABLE_KEY
#
# These values should be set as environment variables during the build process
# and will be embedded in the static files uploaded to S3
