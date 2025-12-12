# Schema Initialization for Aurora PostgreSQL
# Automatically initializes database schema from data/schema.sql after cluster is created
# This ensures the business_events table and all required tables exist before Lambda functions are deployed

resource "null_resource" "schema_init" {
  depends_on = [
    aws_rds_cluster_instance.this,
    aws_rds_cluster.this
  ]

  triggers = {
    cluster_endpoint = aws_rds_cluster.this.endpoint
    schema_hash      = filemd5("${path.module}/../../../data/schema.sql")
    database_name    = var.database_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.module}/../../../ && \
      python3 scripts/init-aurora-schema.py
    EOT

    environment = {
      AURORA_ENDPOINT   = aws_rds_cluster.this.endpoint
      AURORA_PORT       = tostring(aws_rds_cluster.this.port)
      DATABASE_NAME     = var.database_name
      DATABASE_USER     = var.database_user
      DATABASE_PASSWORD = var.database_password
    }

    on_failure = fail
  }
}

