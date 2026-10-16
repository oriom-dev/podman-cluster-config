env "local" {
  src = "file://schema.pg.hcl"
  url = getenv("DB_URL")
  dev = "docker://postgres/16/dev"
}