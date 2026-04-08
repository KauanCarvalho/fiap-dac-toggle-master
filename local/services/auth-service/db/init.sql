CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    
    -- key_hash armazena o hash SHA-256 da chave, que tem 64 caracteres hexadecimais
    key_hash VARCHAR(64) NOT NULL UNIQUE, 
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO api_keys (name, key_hash) 
VALUES ('local-evaluation-service-seed-key', 'b06dc739b0b7498efc16dc28a1ce7387781fcbeb83d388644e3ddc96230ded8c')
ON CONFLICT (key_hash) DO NOTHING;