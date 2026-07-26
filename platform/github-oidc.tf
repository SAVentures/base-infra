# The role every product's GitHub Actions deploy workflow assumes via OIDC.
#
# Adopted into Terraform on 2026-07-26. It was created by hand and sat
# unmanaged for years, which is exactly why it was worth importing: it is the
# single point of failure for all three products' deploys, and when its trust
# policy stopped matching a new repository's token there was no plan anywhere
# that would have shown the problem. See the sub-claim comment below.
#
# The OIDC provider itself stays unmanaged and is read as a data source —
# it is shared with non-GitHub identity federation in this account.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-admin-aws"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = var.github_oidc_allowed_subjects
        }
      }
    }]
  })
}

# AdministratorAccess. Imported rather than narrowed: scoping this down is a
# real change in blast radius that deserves its own review, not a side effect
# of adopting the role. Managed here so reading this file does not leave the
# impression that the role is unprivileged.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

import {
  to = aws_iam_role.github_actions
  id = "github-actions-admin-aws"
}

import {
  to = aws_iam_role_policy_attachment.github_actions_admin
  id = "github-actions-admin-aws/arn:aws:iam::aws:policy/AdministratorAccess"
}
