CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    
    -- key_hash armazena o hash SHA-256 da chave, que tem 64 caracteres hexadecimais
    key_hash VARCHAR(64) NOT NULL UNIQUE, 
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO api_keys (name, key_hash) 
VALUES ('local-evaluation-service-seed-key', 'd764f1dc515db52f4473c3158a64c651c724f1d3229e685388ff38938444859d')
ON CONFLICT (key_hash) DO NOTHING;