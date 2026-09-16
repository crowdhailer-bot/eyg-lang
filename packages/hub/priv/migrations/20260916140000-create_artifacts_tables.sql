--- migration:up

CREATE TABLE artifacts (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL,
  ip          INET        NOT NULL,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ON artifacts (ip, inserted_at);

CREATE TABLE artifact_files (
  artifact_id UUID  NOT NULL REFERENCES artifacts(id),
  path        TEXT  NOT NULL,
  media_type  TEXT  NOT NULL,
  content     BYTEA NOT NULL,
  PRIMARY KEY (artifact_id, path)
);

--- migration:down

DROP TABLE artifact_files;
DROP TABLE artifacts;

--- migration:end
