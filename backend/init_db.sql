-- Executado automaticamente pelo Docker na primeira inicialização
-- O banco "cashback_db" e o usuário "cashback_user" já são criados
-- pelas variáveis POSTGRES_DB / POSTGRES_USER do docker-compose.

CREATE TABLE IF NOT EXISTS queries (
    id             SERIAL          PRIMARY KEY,
    ip             VARCHAR(45)     NOT NULL,
    client_type    VARCHAR(10)     NOT NULL,
    purchase_value NUMERIC(12, 2)  NOT NULL,
    cashback_value NUMERIC(12, 2)  NOT NULL,
    created_at     TIMESTAMP       NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_queries_ip         ON queries (ip);
CREATE INDEX IF NOT EXISTS idx_queries_created_at ON queries (created_at DESC);
