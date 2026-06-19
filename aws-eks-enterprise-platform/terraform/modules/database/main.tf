###############################################################################
# Database — Aurora PostgreSQL serverless-compatible cluster
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Subnet Group ──────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name        = "${var.name_prefix}-db-subnet-group"
  subnet_ids  = var.isolated_subnet_ids
  description = "${var.name_prefix} isolated subnets for Aurora"
  tags        = merge(var.tags, { Name = "${var.name_prefix}-db-subnet-group" })
}

# ── Security Group ────────────────────────────────────────────────────────────
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "Aurora PostgreSQL — allow 5432 from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.allowed_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-sg" })
}

# ── Cluster Parameter Group ───────────────────────────────────────────────────
resource "aws_rds_cluster_parameter_group" "main" {
  name        = "${var.name_prefix}-cluster-pg"
  family      = "aurora-postgresql15"
  description = "${var.name_prefix} Aurora PostgreSQL 15 cluster parameters"

  # Full audit trail — log all statements, connections, and disconnections
  parameter {
    name  = "log_statement"
    value = "all"  # was 'ddl' — changed to 'all' for complete audit trail
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }
  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = var.tags
}

# ── Instance Parameter Group ──────────────────────────────────────────────────
resource "aws_db_parameter_group" "main" {
  name        = "${var.name_prefix}-instance-pg"
  family      = "aurora-postgresql15"
  description = "${var.name_prefix} Aurora PostgreSQL 15 instance parameters"
  tags        = var.tags
}

# ── Aurora Cluster ────────────────────────────────────────────────────────────
resource "aws_rds_cluster" "main" {
  cluster_identifier              = "${var.name_prefix}-aurora"
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  database_name                   = var.database_name
  master_username                 = var.master_username
  master_password                 = var.master_password
  db_subnet_group_name            = aws_db_subnet_group.main.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # Allow EKS pods to authenticate with short-lived IAM tokens via IRSA
  # instead of long-lived master_password credentials
  iam_database_authentication_enabled = true

  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.environment != "prod"
  final_snapshot_identifier       = var.environment == "prod" ? "${var.name_prefix}-final-snapshot" : null
  copy_tags_to_snapshot           = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(var.tags, { Name = "${var.name_prefix}-aurora" })
}

# ── Cluster Instances ─────────────────────────────────────────────────────────
resource "aws_rds_cluster_instance" "main" {
  count = var.instance_count

  identifier           = "${var.name_prefix}-aurora-${count.index}"
  cluster_identifier   = aws_rds_cluster.main.id
  instance_class       = var.instance_class
  engine               = aws_rds_cluster.main.engine
  engine_version       = aws_rds_cluster.main.engine_version
  db_parameter_group_name = aws_db_parameter_group.main.name

  performance_insights_enabled    = var.enable_performance_insights
  performance_insights_kms_key_id = var.enable_performance_insights ? var.kms_key_arn : null

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  auto_minor_version_upgrade = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-aurora-${count.index}"
    Role = count.index == 0 ? "writer" : "reader"
  })
}

# ── Enhanced Monitoring Role ──────────────────────────────────────────────────
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.name_prefix}-rds-monitoring-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── Secrets Manager — DB credentials ─────────────────────────────────────────
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.name_prefix}/db/credentials"
  description             = "Aurora PostgreSQL admin credentials for ${var.name_prefix}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.environment == "prod" ? 30 : 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = var.master_password
    engine   = "aurora-postgresql"
    host     = aws_rds_cluster.main.endpoint
    port     = 5432
    dbname   = var.database_name
  })
}
