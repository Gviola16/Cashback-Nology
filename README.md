# CashVault — Sistema de Cashback

## Estrutura

```
cashvault/
├── backend/
│   ├── main.py           # API FastAPI
│   ├── requirements.txt
│   ├── init_db.sql       # Script de criação do banco
│   └── .env.example      # Template de variáveis de ambiente
└── frontend/
    └── index.html        # SPA estática
```

## 1. Configurar o Banco PostgreSQL

```bash
# Crie o banco e o usuário
psql -U postgres -f backend/init_db.sql
```

## 2. Configurar o Backend

```bash
cd backend

# Criar e ativar virtualenv
python -m venv venv
source venv/bin/activate  # Linux/Mac
# venv\Scripts\activate   # Windows

# Instalar dependências
pip install -r requirements.txt

# Configurar variáveis de ambiente
cp .env.example .env
# Edite .env com as credenciais corretas

# Rodar a API
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

A API ficará disponível em `http://localhost:8000`  
Documentação automática (Swagger): `http://localhost:8000/docs`

## 3. Rodar o Frontend

O frontend é um arquivo HTML estático. Basta abrir no navegador:

```bash
# Opção 1: abrir diretamente
xdg-open frontend/index.html

# Opção 2: servir com Python (recomendado para evitar problemas de CORS)
cd frontend
python -m http.server 3000
# Acesse http://localhost:3000
```

> **Nota:** Se o backend não estiver rodando em `localhost:8000`, edite a linha
> `const API_BASE = 'http://localhost:8000';` em `frontend/index.html`.

## Regras de Negócio

| Etapa | Regra | Fonte |
|-------|-------|-------|
| 1 | Cashback base = **5%** do valor da compra | Doc 1 – Product Owner |
| 2 | Compras **> R$ 500** → cashback base × 2 | Doc 2 – Diretor Comercial |
| 3 | Clientes **VIP** → cashback × 1.10 (+10% bônus) | Doc 1 + Reunião |

**Exemplos:**

| Cliente | Valor | Base | 2× | Bônus VIP | Total |
|---------|-------|------|----|-----------|-------|
| Regular | R$300 | R$15,00 | — | — | **R$15,00** |
| Regular | R$600 | R$30,00 | R$60,00 | — | **R$60,00** |
| VIP     | R$300 | R$15,00 | — | R$1,50 | **R$16,50** |
| VIP     | R$600 | R$30,00 | R$60,00 | R$6,00 | **R$66,00** |

## Endpoints da API

| Método | Rota | Descrição |
|--------|------|-----------|
| POST | `/api/cashback` | Calcula e registra uma consulta |
| GET | `/api/history` | Retorna histórico do IP atual |
| GET | `/api/health` | Health check |

### POST `/api/cashback`
```json
// Request
{ "client_type": "regular", "purchase_value": 600.00 }

// Response
{
  "success": true,
  "ip": "127.0.0.1",
  "base_cashback": 60.00,
  "vip_bonus": 0.0,
  "total_cashback": 60.00,
  "doubled": true
}
```
