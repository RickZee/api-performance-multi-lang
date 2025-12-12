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
      export PGPASSWORD='${replace(replace(var.database_password, "'", "'\"'\"'"), "$", "\\$")}'
      psql -h ${aws_rds_cluster.this.endpoint} \
           -U ${var.database_user} \
           -d ${var.database_name} \
           -p ${aws_rds_cluster.this.port} \
           -f ${path.module}/../../../data/schema.sql \
           -v ON_ERROR_STOP=1
    EOT

    on_failure = fail
  }
}

