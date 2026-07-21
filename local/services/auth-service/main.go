package main

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"os"

	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// App struct (para injeção de dependência)
type App struct {
	DB        *sql.DB
	MasterKey string
}

func main() {
	// Inicializa o OTel Tracer Provider
	shutdownTracer, err := initTracer("auth-service")
	if err != nil {
		log.Printf("Aviso: Falha ao inicializar tracer OTel: %v", err)
	} else {
		defer shutdownTracer(context.Background())
	}

	// Inicializa o OTel Meter Provider (métricas HTTP — Fase 4)
	shutdownMeter, err := initMeter("auth-service")
	if err != nil {
		log.Printf("Aviso: Falha ao inicializar meter OTel: %v", err)
	} else {
		defer shutdownMeter(context.Background())
	}

	// Carrega o .env para desenvolvimento local. Em produção, isso não fará nada.
	_ = godotenv.Load()

	// --- Configuração ---
	port := os.Getenv("PORT")
	if port == "" {
		port = "8001" // Porta padrão
	}

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL deve ser definida")
	}

	masterKey := os.Getenv("MASTER_KEY")
	if masterKey == "" {
		log.Fatal("MASTER_KEY deve ser definida")
	}

	// --- Conexão com o Banco ---
	db, err := connectDB(databaseURL)
	if err != nil {
		log.Fatalf("Não foi possível conectar ao banco de dados: %v", err)
	}
	defer db.Close()

	app := &App{
		DB:        db,
		MasterKey: masterKey,
	}

	// --- Rotas da API ---
	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.healthHandler)

	// Endpoint público para validar uma chave
	mux.HandleFunc("/validate", app.validateKeyHandler)

	// Endpoints de "admin" para criar/gerenciar chaves
	// Eles são protegidos pelo middleware de autenticação
	mux.Handle("/admin/keys", app.masterKeyAuthMiddleware(http.HandlerFunc(app.createKeyHandler)))

	log.Printf("Serviço de Autenticação (Go) rodando na porta %s", port)

	// Métricas HTTP (Fase 4): http_requests_total / http_request_duration_seconds
	metricsRecorder, err := newHTTPMetrics("auth-service")
	if err != nil {
		log.Fatalf("Falha ao criar métricas HTTP: %v", err)
	}

	// Encapsula o handler principal com OTel HTTP middleware (tracing) + métricas
	otelHandler := otelhttp.NewHandler(mux, "auth-service-http")
	handler := metricsRecorder.middleware(otelHandler)

	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatal(err)
	}
}

// connectDB inicializa e testa a conexão com o PostgreSQL
func connectDB(databaseURL string) (*sql.DB, error) {
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, err
	}

	if err = db.Ping(); err != nil {
		return nil, err
	}

	log.Println("Conectado ao PostgreSQL com sucesso!")
	return db, nil
}
