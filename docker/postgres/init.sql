-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- Enable trigram extension for faster LIKE matches
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Grant ownership to mmw user
ALTER TABLE spatial_ref_sys OWNER TO mmw;
