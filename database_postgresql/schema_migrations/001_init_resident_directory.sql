-- Resident Directory App - Initial Schema (v1)
-- NOTE:
-- This file is provided for documentation/repeatability, but in this environment
-- migrations are applied via individual `psql -c "..."` statements (per container rules).
-- The database has been brought to this schema state.

-- Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Enums
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'role_type') THEN
    CREATE TYPE role_type AS ENUM ('resident','staff','admin');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'auth_provider') THEN
    CREATE TYPE auth_provider AS ENUM ('email','phone','invitation','supabase');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'approval_state') THEN
    CREATE TYPE approval_state AS ENUM ('pending','approved','rejected','suspended');
  END IF;
END$$;

-- Core users
CREATE TABLE IF NOT EXISTS app_user (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext UNIQUE,
  phone text UNIQUE,
  password_hash text,
  role role_type NOT NULL DEFAULT 'resident',
  approval_state approval_state NOT NULL DEFAULT 'pending',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT app_user_email_or_phone_chk CHECK (email IS NOT NULL OR phone IS NOT NULL)
);

-- Auth identities (email/phone/invite/external)
CREATE TABLE IF NOT EXISTS auth_identity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  provider auth_provider NOT NULL,
  provider_subject text,
  email citext,
  phone text,
  invitation_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(provider, provider_subject),
  UNIQUE(provider, email),
  UNIQUE(provider, phone),
  UNIQUE(invitation_code)
);

-- Resident profile
CREATE TABLE IF NOT EXISTS resident_profile (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid UNIQUE REFERENCES app_user(id) ON DELETE SET NULL,
  full_name text NOT NULL,
  unit_number text NOT NULL,
  building text,
  floor text,
  photo_url text,
  email citext,
  phone text,
  family_members jsonb NOT NULL DEFAULT '[]'::jsonb,
  vehicles jsonb NOT NULL DEFAULT '[]'::jsonb,
  emergency_contacts jsonb NOT NULL DEFAULT '[]'::jsonb,
  interests text[] NOT NULL DEFAULT ARRAY[]::text[],
  bio text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Privacy settings
CREATE TABLE IF NOT EXISTS resident_privacy_settings (
  resident_id uuid PRIMARY KEY REFERENCES resident_profile(id) ON DELETE CASCADE,
  show_email boolean NOT NULL DEFAULT false,
  show_phone boolean NOT NULL DEFAULT false,
  show_photo boolean NOT NULL DEFAULT true,
  show_family_members boolean NOT NULL DEFAULT false,
  show_vehicles boolean NOT NULL DEFAULT false,
  show_emergency_contacts boolean NOT NULL DEFAULT false,
  show_interests boolean NOT NULL DEFAULT true,
  allow_in_app_messages_only boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Announcements
CREATE TABLE IF NOT EXISTS announcement (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  body text NOT NULL,
  created_by uuid REFERENCES app_user(id) ON DELETE SET NULL,
  is_published boolean NOT NULL DEFAULT true,
  published_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Audit log
CREATE TABLE IF NOT EXISTS audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  ip_address inet,
  user_agent text,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- updated_at helper
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers
DROP TRIGGER IF EXISTS trg_app_user_updated_at ON app_user;
CREATE TRIGGER trg_app_user_updated_at
BEFORE UPDATE ON app_user
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_resident_profile_updated_at ON resident_profile;
CREATE TRIGGER trg_resident_profile_updated_at
BEFORE UPDATE ON resident_profile
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_resident_privacy_settings_updated_at ON resident_privacy_settings;
CREATE TRIGGER trg_resident_privacy_settings_updated_at
BEFORE UPDATE ON resident_privacy_settings
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Indexes for search/filter
CREATE INDEX IF NOT EXISTS idx_app_user_role ON app_user(role);
CREATE INDEX IF NOT EXISTS idx_app_user_approval_state ON app_user(approval_state);

CREATE INDEX IF NOT EXISTS idx_resident_profile_unit ON resident_profile(unit_number);
CREATE INDEX IF NOT EXISTS idx_resident_profile_building_floor ON resident_profile(building, floor);
CREATE INDEX IF NOT EXISTS idx_resident_profile_full_name_trgm ON resident_profile USING gin (full_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_resident_profile_interests_gin ON resident_profile USING gin (interests);

CREATE INDEX IF NOT EXISTS idx_announcement_published_at ON announcement(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log(created_at DESC);
