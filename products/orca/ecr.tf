resource "aws_ecr_repository" "api" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "render_service" {
  name                 = var.render_service_ecr_repository
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Remotion images carry a full Chromium; without expiry the repo grows by
# ~1 GB per merge to main. Keep the last 10 and let the rest age out.
resource "aws_ecr_lifecycle_policy" "render_service" {
  repository = aws_ecr_repository.render_service.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire all but the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
