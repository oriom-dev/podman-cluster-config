schema "public" {}

table "user" {
  schema = schema.public

  column "id" {
    type = text
    null = false
  }

  column "name" {
    type = text
    null = false
  }

  column "email" {
    type = text
    null = false
  }

  column "emailVerified" {
    type = boolean
    null = false
  }

  column "image" {
    type = text
  }

  column "createdAt" {
    type = timestamptz
    null = false
  }

  column "updatedAt" {
    type = timestamptz
    null = false
  }

  primary_key {
    columns = [column.id]
  }

  unique "user_email_unique" {
    columns = [column.email]
  }
}

table "session" {
  schema = schema.public

  column "id" {
    type = text
    null = false
  }

  column "expiresAt" {
    type = timestamptz
    null = false
  }

  column "token" {
    type = text
    null = false
  }

  column "createdAt" {
    type = timestamptz
    null = false
  }

  column "updatedAt" {
    type = timestamptz
    null = false
  }

  column "ipAddress" {
    type = text
  }

  column "userAgent" {
    type = text
  }

  column "userId" {
    type = text
    null = false
  }

  primary_key {
    columns = [column.id]
  }

  unique "session_token_unique" {
    columns = [column.token]
  }

  index "session_user_id_idx" {
    columns = [column.userId]
  }

  foreign_key "session_user_id_fkey" {
    columns = [column.userId]
    ref_columns = [table.user.column.id]
    on_delete = CASCADE
  }
}

table "account" {
  schema = schema.public

  column "id" {
    type = text
    null = false
  }

  column "accountId" {
    type = text
    null = false
  }

  column "providerId" {
    type = text
    null = false
  }

  column "userId" {
    type = text
    null = false
  }

  column "accessToken" {
    type = text
  }

  column "refreshToken" {
    type = text
  }

  column "idToken" {
    type = text
  }

  column "accessTokenExpiresAt" {
    type = timestamptz
  }

  column "refreshTokenExpiresAt" {
    type = timestamptz
  }

  column "scope" {
    type = text
  }

  column "password" {
    type = text
  }

  column "createdAt" {
    type = timestamptz
    null = false
  }

  column "updatedAt" {
    type = timestamptz
    null = false
  }

  primary_key {
    columns = [column.id]
  }

  unique "account_provider_account_unique" {
    columns = [column.providerId, column.accountId]
  }

  index "account_user_id_idx" {
    columns = [column.userId]
  }

  foreign_key "account_user_id_fkey" {
    columns = [column.userId]
    ref_columns = [table.user.column.id]
    on_delete = CASCADE
  }
}

table "verification" {
  schema = schema.public

  column "id" {
    type = text
    null = false
  }

  column "identifier" {
    type = text
    null = false
  }

  column "value" {
    type = text
    null = false
  }

  column "expiresAt" {
    type = timestamptz
    null = false
  }

  column "createdAt" {
    type = timestamptz
    null = false
  }

  column "updatedAt" {
    type = timestamptz
    null = false
  }

  primary_key {
    columns = [column.id]
  }

  index "verification_identifier_idx" {
    columns = [column.identifier]
  }
}

table "minecraft_player_link" {
  schema = schema.public

  column "uuid" {
    type = text
    null = false
  }

  column "username" {
    type = text
    null = false
  }

  column "userId" {
    type = text
    null = false
  }

  column "createdAt" {
    type = timestamptz
    null = false
  }

  column "updatedAt" {
    type = timestamptz
    null = false
  }

  primary_key {
    columns = [column.uuid]
  }

  index "minecraft_player_link_user_id_idx" {
    columns = [column.userId]
  }

  foreign_key "minecraft_player_link_user_id_fkey" {
    columns = [column.userId]
    ref_columns = [table.user.column.id]
    on_delete = CASCADE
  }
}

table "minecraft_access_challenge" {
  schema = schema.public

  column "code" {
    type = text
    null = false
  }

  column "playerUuid" {
    type = text
    null = false
  }

  column "playerUsername" {
    type = text
    null = false
  }

  column "attemptedHost" {
    type = text
    null = false
  }

  column "createdAt" {
    type = timestamptz
    null = false
  }

  column "expiresAt" {
    type = timestamptz
    null = false
  }

  column "consumedAt" {
    type = timestamptz
  }

  column "consumedByUserId" {
    type = text
  }

  primary_key {
    columns = [column.code]
  }

  index "minecraft_access_challenge_expires_at_idx" {
    columns = [column.expiresAt]
  }

  index "minecraft_access_challenge_attempted_host_idx" {
    columns = [column.attemptedHost]
  }

  index "minecraft_access_challenge_player_uuid_idx" {
    columns = [column.playerUuid]
  }

  foreign_key "minecraft_access_challenge_consumed_by_user_id_fkey" {
    columns = [column.consumedByUserId]
    ref_columns = [table.user.column.id]
    on_delete = SET_NULL
  }
}

table "user_domain_grant" {
  schema = schema.public

  column "userId" {
    type = text
    null = false
  }

  column "domain" {
    type = text
    null = false
  }

  column "includeSubdomains" {
    type = boolean
    null = false
  }

  column "createdAt" {
    type = timestamptz
    null = false
  }

  column "updatedAt" {
    type = timestamptz
    null = false
  }

  primary_key {
    columns = [column.userId, column.domain]
  }

  index "user_domain_grant_user_id_idx" {
    columns = [column.userId]
  }

  foreign_key "user_domain_grant_user_id_fkey" {
    columns = [column.userId]
    ref_columns = [table.user.column.id]
    on_delete = CASCADE
  }
}

table "audit_log" {
  schema = schema.public

  column "id" {
    type = text
    null = false
  }

  column "action" {
    type = text
    null = false
  }

  column "actorUserId" {
    type = text
  }

  column "actorEmail" {
    type = text
  }

  column "targetUserId" {
    type = text
  }

  column "targetEmail" {
    type = text
  }

  column "metadata" {
    type = text
    null = false
  }

  column "createdAt" {
    type = timestamptz
    null = false
  }

  primary_key {
    columns = [column.id]
  }

  index "audit_log_created_at_idx" {
    columns = [column.createdAt]
  }

  index "audit_log_action_idx" {
    columns = [column.action]
  }
}